# Rastreador interno de erros (substituto caseiro do Sentry).
#
# NÃO usa TenantScoped de propósito: a visão é do Admin do Sistema
# (cross-tenant) e o registro precisa funcionar mesmo com o tenant
# deletado/quebrado — tenant_id é um bigint solto, sem FK.
#
# ErrorEvent.record! NUNCA levanta exceção e NUNCA grava se a tabela ainda não
# existe (deploy antes da migration): o rastreador não pode derrubar a request
# ou o job que já está falhando.
class ErrorEvent < ApplicationRecord
  SOURCES = %w[request job manual].freeze
  SEVERITIES = %w[error warning info].freeze

  APP_FRAMES_LIMIT = 5
  MESSAGE_LIMIT = 2_000
  BACKTRACE_LINES_LIMIT = 60
  ALERT_THROTTLE = 1.hour

  belongs_to :tenant, optional: true

  scope :recent, -> { order(last_seen_at: :desc) }
  scope :unresolved, -> { where(resolved_at: nil) }
  scope :resolved, -> { where.not(resolved_at: nil) }
  scope :by_class, ->(klass) { where(exception_class: klass) }
  scope :by_source, ->(source) { where(source: source) }

  class << self
    # Registra uma ocorrência de erro agrupando pelo fingerprint estável.
    # find + update atômico ou create (com retry em RecordNotUnique).
    def record!(exception, source:, context: {}, severity: "error")
      return nil unless exception.respond_to?(:message)
      return nil unless storage_ready?

      fingerprint = fingerprint_for(exception)
      now = Time.current
      payload = context_payload(context)
      severity = normalize_severity(severity)

      event = find_by(fingerprint: fingerprint)
      if event
        register_occurrence(event, now: now, payload: payload, severity: severity)
      else
        begin
          event = create!(
            fingerprint: fingerprint,
            exception_class: exception.class.name,
            message: exception.message.to_s.truncate(MESSAGE_LIMIT),
            backtrace: Array(exception.backtrace).first(BACKTRACE_LINES_LIMIT).join("\n"),
            source: source.to_s,
            severity: severity,
            tenant_id: payload["tenant_id"] || Current.tenant&.id,
            context: payload,
            occurrences_count: 1,
            first_seen_at: now,
            last_seen_at: now
          )
          notify(event, reopened: false)
        rescue ActiveRecord::RecordNotUnique
          # Corrida entre processos: outro worker criou o mesmo fingerprint.
          event = find_by(fingerprint: fingerprint)
          register_occurrence(event, now: now, payload: payload, severity: severity) if event
        end
      end

      event
    rescue StandardError => e
      Rails.logger.error("[ERROR_TRACKER] falha ao registrar #{exception.class}: #{e.class}: #{e.message}")
      nil
    end

    # Fingerprint estável: classe + mensagem normalizada (ids/hex/uuids viram
    # placeholder para não explodir a cardinalidade) + top frames do app.
    def fingerprint_for(exception)
      Digest::SHA256.hexdigest(
        [
          exception.class.name,
          normalized_message(exception.message),
          app_frames(exception.backtrace).join("\n")
        ].join("|")
      )
    end

    def normalized_message(message)
      msg = message.to_s[0, 1_000].dup
      msg.gsub!(/\h{8}-\h{4}-\h{4}-\h{4}-\h{12}/, "<uuid>")
      msg.gsub!(/0x\h+/, "<hex>")
      msg.gsub!(/\b\h{8,}\b/, "<hex>")
      msg.gsub!(/\d{3,}/, "<num>")
      msg
    end

    # Só frames dentro do app (Rails.root, excluindo gems/vendor), com o
    # prefixo do root removido — em deploys via releases/N o path muda a cada
    # release e quebraria a estabilidade do fingerprint.
    def app_frames(backtrace)
      root = Rails.root.to_s
      Array(backtrace)
        .select { |line| line.start_with?(root) }
        .reject { |line| line.include?("/gems/") || line.include?("/vendor/") }
        .first(APP_FRAMES_LIMIT)
        .map { |line| line.delete_prefix(root).delete_prefix("/") }
    end

    # Memoizado com reset: evita consultar o information_schema a cada erro,
    # mas permite reavaliar depois de rodar a migration (reset_storage_check!).
    def storage_ready?
      return @storage_ready unless @storage_ready.nil?

      @storage_ready = connection.data_source_exists?(table_name)
    rescue StandardError
      false
    end

    def reset_storage_check!
      @storage_ready = nil
    end

    private

    def register_occurrence(event, now:, payload:, severity:)
      reopened = event.resolved_at.present?
      update_counters(event.id, occurrences_count: 1)
      where(id: event.id).update_all(
        last_seen_at: now,
        context: payload,
        severity: severity,
        resolved_at: nil, # reincidência reabre o evento
        updated_at: now
      )
      notify(event, reopened: true) if reopened
      event
    end

    def normalize_severity(severity)
      value = severity.to_s
      SEVERITIES.include?(value) ? value : "error"
    end

    # Contexto serializável e enxuto: valores estranhos viram o nome da classe.
    def context_payload(context)
      (context || {}).each_with_object({}) do |(key, value), hash|
        hash[key.to_s] = serializable_value(value)
      end
    rescue StandardError
      {}
    end

    def serializable_value(value, depth = 0)
      return "..." if depth > 4

      case value
      when Hash
        value.first(30).to_h { |k, v| [k.to_s, serializable_value(v, depth + 1)] }
      when Array
        value.first(20).map { |v| serializable_value(v, depth + 1) }
      when String
        value.truncate(500)
      when Symbol, Numeric, TrueClass, FalseClass, NilClass
        value
      else
        value.class.name
      end
    end

    # Alerta de fingerprint novo (ou reincidente após resolvido): log grepável
    # sempre; e-mail global só com ENV['ERROR_ALERT_EMAIL'] presente, com
    # throttle de 1h por fingerprint via last_alerted_at.
    def notify(event, reopened:)
      Rails.logger.error(
        "[ERROR_TRACKER] #{reopened ? 'reincidência' : 'novo erro'} " \
        "fingerprint=#{event.fingerprint} #{event.exception_class}: #{event.message.to_s.truncate(140)}"
      )
      deliver_alert(event)
    rescue StandardError => e
      Rails.logger.error("[ERROR_TRACKER] alerta falhou: #{e.class}: #{e.message}")
    end

    def deliver_alert(event)
      recipients = ENV["ERROR_ALERT_EMAIL"].to_s.split(",").map(&:strip).reject(&:empty?)
      return if recipients.empty?

      # Claim atômico do throttle: só um processo dentro da janela envia.
      claimed = where(id: event.id)
        .where("last_alerted_at IS NULL OR last_alerted_at <= ?", ALERT_THROTTLE.ago)
        .update_all(last_alerted_at: Time.current)
      return if claimed.zero?

      ErrorAlertMailer.with(error_event_id: event.id, recipients: recipients).new_error_event.deliver_later
    end
  end

  def resolved?
    resolved_at.present?
  end

  def resolve!
    update!(resolved_at: Time.current)
  end

  def reopen!
    update!(resolved_at: nil)
  end
end
