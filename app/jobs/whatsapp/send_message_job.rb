module Whatsapp
  class SendMessageJob < ApplicationJob
    queue_as :realtime

    # Falha transitória em que a chamada à Meta comprovadamente NÃO entregou a
    # mensagem (conexão recusada/DNS/timeout de ABERTURA, 429 ou 5xx com
    # resposta recebida) — seguro re-tentar sem risco de dupla entrega.
    # Timeout de LEITURA (pós-request) fica de fora: a Meta pode ter processado.
    class TransientSendError < StandardError; end

    CONNECTION_PHASE_ERROR_PATTERNS = [
      /failed to open tcp connection/i,
      /connection refused/i,
      /getaddrinfo/i,
      /net::opentimeout/i,
      /execution expired/i, # Net::OpenTimeout; read timeout vira "Net::ReadTimeout with ..."
      /ssl_connect/i,
      /ehostunreach|enetunreach|econnrefused/i
    ].freeze

    retry_on TransientSendError, wait: :polynomially_longer, attempts: 3 do |job, error|
      job.mark_failed_after_retries(error)
    end

    def self.dispatch(message_id, tenant_id:)
      if inline_dispatch?
        perform_now(message_id, tenant_id: tenant_id)
      else
        perform_later(message_id, tenant_id: tenant_id)
      end
    end

    def self.inline_dispatch?
      override = ENV["WHATSAPP_SEND_INLINE"].to_s.strip
      return ActiveModel::Type::Boolean.new.cast(override) if override.present?

      Rails.env.development?
    end

    def perform(message_id, tenant_id: nil)
      message = message_scope(tenant_id).find_by(id: message_id)
      return unless message&.outbound?

      conversation = message.whatsapp_conversation
      return unless message.tenant_id == conversation.tenant_id

      Current.set(tenant: conversation.tenant) do
        recipient = conversation.cloud_recipient # telefone ou BSUID
        return update_message_status!(message, status: "failed", error_message: "Conversa sem telefone ou BSUID") if recipient.blank?

        client = Whatsapp::CloudClient.new(WhatsappBusinessIntegration.current(conversation.tenant))

        result =
          if message.msg_type == "template" && message.template_name.present?
            client.send_template(to: recipient, name: message.template_name)
          elsif message.media?
            send_media_message(client, recipient, message)
          else
            client.send_text(to: recipient, body: message.body, context_message_id: message.try(:context_wa_message_id))
          end

        if result[:ok]
          update_message_status!(message, status: "sent", wa_message_id: result[:message_id], sent_at: Time.current, error_message: nil)
        elsif retryable_send_failure?(result)
          raise TransientSendError, result[:error].to_s.presence || "Falha transitória no envio WhatsApp"
        else
          update_message_status!(message, status: "failed", error_message: result[:error].to_s.truncate(250))
        end
      end
    end

    # Esgotadas as tentativas do retry_on: aí sim a falha vira definitiva.
    def mark_failed_after_retries(error)
      message_id = arguments.first
      options = arguments.second
      tenant_id = options.is_a?(Hash) ? options[:tenant_id] : nil
      message = message_scope(tenant_id).find_by(id: message_id)
      return unless message&.outbound?

      Current.set(tenant: message.tenant) do
        update_message_status!(message, status: "failed", error_message: error.message.to_s.truncate(250))
      end
    end

    private

    def retryable_send_failure?(result)
      status = result[:status].to_i
      return true if status == 429 || (500..599).cover?(status)
      return false unless status.zero?

      # status 0 = exceção engolida pelo CloudClient: só re-tenta quando a
      # mensagem de erro comprova falha na FASE DE CONEXÃO (request não saiu).
      message = result[:error].to_s
      return false if message.match?(/read.?timeout/i)

      CONNECTION_PHASE_ERROR_PATTERNS.any? { |pattern| message.match?(pattern) }
    end

    def message_scope(tenant_id)
      # fail-closed: sem tenant o job no-opa (e avisa) em vez de operar
      # cross-tenant. O dispatch sempre passa tenant_id.
      if tenant_id.blank?
        Rails.logger.warn("[WhatsappMessage] job sem tenant_id — ignorado")
        return WhatsappMessage.none
      end

      tenant = Tenant.find_by(id: tenant_id)
      tenant ? tenant.whatsapp_messages : WhatsappMessage.none
    end

    def send_media_message(client, recipient, message)
      uploaded_media_id = nil

      if message.media_file.attached?
        # .mov do iPhone etc.: converte para MP4 antes de validar/subir
        conversion = Whatsapp::MediaConverter.ensure_supported!(message)
        return conversion unless conversion[:ok]

        message.media_file.reload if conversion[:converted]
        media_validation = Whatsapp::MediaSupport.validation_for(message.media_file.blob)
        return media_validation unless media_validation[:ok]

        message.media_file.blob.open do |file|
          upload = client.upload_message_media(
            file_name: message.media_file.filename.to_s,
            content_type: media_validation[:content_type],
            type: media_validation[:type],
            io: file
          )
          return upload unless upload[:ok]

          uploaded_media_id = upload[:media_id]
        end
      end

      if uploaded_media_id.blank? && message.media_url.blank?
        return { ok: false, error: "Mídia sem arquivo anexado nem link remoto para envio." }
      end

      client.send_media(
        to: recipient,
        type: message.msg_type,
        media_id: uploaded_media_id,
        link: uploaded_media_id.present? ? nil : message.media_url,
        caption: message.body,
        filename: message.media_name,
        context_message_id: message.try(:context_wa_message_id)
      )
    end

    def update_message_status!(message, attrs)
      message.update!(attrs)
      Whatsapp::ThreadBroadcaster.message_updated(message)
    end
  end
end
