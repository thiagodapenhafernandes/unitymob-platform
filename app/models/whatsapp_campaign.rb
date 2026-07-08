class WhatsappCampaign < ApplicationRecord
  include TenantScoped

  STATUSES = %w[draft scheduled processing paused completed cancelled failed].freeze
  AUDIENCE_MODES = %w[filters spreadsheet saved_audience].freeze
  RESPONSE_ACTIONS = {
    "generate_lead" => "Converter em lead e distribuir",
    "send_message" => "Responder com mensagem",
    "create_task" => "Criar tarefa comercial",
    "mark_no_interest" => "Marcar sem interesse",
    "unsubscribe" => "Descadastrar contato",
    "ignore" => "Apenas registrar"
  }.freeze

  belongs_to :whatsapp_template
  belongs_to :created_by, class_name: "AdminUser"
  belongs_to :whatsapp_sender_number, optional: true
  belongs_to :automation_workflow, optional: true
  has_one_attached :audience_file
  has_many :campaign_messages,
           class_name: "WhatsappCampaignMessage",
           dependent: :destroy,
           inverse_of: :whatsapp_campaign
  has_many :campaign_recipients,
           class_name: "WhatsappCampaignRecipient",
           dependent: :destroy,
           inverse_of: :whatsapp_campaign

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :audience_mode, inclusion: { in: AUDIENCE_MODES }
  validates :group_name, length: { maximum: 80 }
  validates :send_rate, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 500 }
  validates :import_batch_size, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 10_000 }
  validates :import_interval_minutes, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1_440 }
  validate :template_must_be_approved
  validate :associations_must_belong_to_tenant
  validate :scheduled_at_must_be_future, if: -> { status == "scheduled" }
  validate :spreadsheet_requires_file_or_existing_attachment
  validate :response_decisions_must_be_complete

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: %w[scheduled processing paused]) }

  before_validation :set_defaults

  STATUSES.each do |value|
    define_method("#{value}?") { status == value }
  end

  def start!
    return false if processing?
    raise ArgumentError, "Campanha cancelada não pode ser iniciada." if cancelled?
    raise ArgumentError, "Modelo WhatsApp precisa estar aprovado para disparo." unless whatsapp_template&.approved?

    # Gate atômico: cliques duplos e CampaignStartJobs duplicados (re-agendamentos)
    # disputam este UPDATE condicional e só um enfileira o processamento.
    claimed = self.class.where(id: id, status: %w[draft scheduled paused failed]).update_all(
      status: "processing",
      started_at: Time.current,
      failure_reason: nil,
      updated_at: Time.current
    )
    return false if claimed.zero?

    reload
    Whatsapp::CampaignProcessorJob.perform_later(id, tenant_id: tenant_id)
    true
  end

  def pause!
    return unless processing? || scheduled?

    update!(status: "paused", paused_at: Time.current)
    refresh_counters!
  end

  def resume!
    return unless paused?

    update!(status: "processing", paused_at: nil)
    Whatsapp::BulkSendJob.perform_later(id, tenant_id: tenant_id)
  end

  def cancel!
    return if completed? || cancelled?

    update!(status: "cancelled", cancelled_at: Time.current)
  end

  def complete_if_finished!
    return unless processing?
    return if campaign_messages.pending_or_queued.exists?

    refresh_counters!
    update!(status: "completed", completed_at: Time.current)
    emit_event!("whatsapp_campaign_completed", payload: metrics_payload)
  end

  def fail!(reason)
    update!(status: "failed", failure_reason: reason.to_s.truncate(500))
    emit_event!("whatsapp_campaign_failed", payload: metrics_payload.merge(error: failure_reason))
  end

  def pause_for_template_error!(reason)
    update!(
      status: "paused",
      paused_at: Time.current,
      failure_reason: reason.to_s.truncate(500)
    )
    refresh_counters!
  end

  # Erro de autenticação com a Meta (token expirado/revogado): pausar preserva
  # a fila para retomada após reconectar, em vez de queimar todos os envios
  # pendentes como failed com a mesma credencial inválida.
  def pause_for_auth_error!(reason)
    return unless processing?

    update!(
      status: "paused",
      paused_at: Time.current,
      failure_reason: reason.to_s.truncate(500)
    )
    refresh_counters!
  end

  def cancel_pending_messages!
    count = campaign_messages.pending_or_queued.update_all(
      status: "cancelled",
      failed_at: Time.current,
      failure_reason: "Envio pendente cancelado manualmente.",
      updated_at: Time.current
    )
    refresh_counters!
    complete_if_finished!
    count
  end

  def retry_failed_messages!
    raise ArgumentError, "Disparo cancelado não pode ser reprocessado." if cancelled?

    count = campaign_messages.failed.update_all(
      status: "pending",
      queued_at: nil,
      sent_at: nil,
      delivered_at: nil,
      read_at: nil,
      failed_at: nil,
      replied_at: nil,
      failure_reason: nil,
      external_message_id: nil,
      next_retry_at: nil,
      updated_at: Time.current
    )
    return 0 if count.zero?

    refresh_counters!
    update!(status: "processing", paused_at: nil, completed_at: nil, failure_reason: nil) unless processing?
    Whatsapp::BulkSendJob.perform_later(id, tenant_id: tenant_id)
    count
  end

  def refresh_counters!
    counts = campaign_messages.group(:status).count
    update_columns(
      total_recipients: campaign_messages.count,
      sent_count: counts.values_at("sent", "delivered", "read", "replied").compact.sum,
      delivered_count: counts.values_at("delivered", "read", "replied").compact.sum,
      read_count: counts.values_at("read", "replied").compact.sum,
      failed_count: counts.fetch("failed", 0) + counts.fetch("cancelled", 0),
      replied_count: counts.fetch("replied", 0),
      updated_at: Time.current
    )
  end

  def audience_scope
    Whatsapp::CampaignAudienceResolver.call(self, materialize: true).recipients_with_phone
  end

  def metrics_payload
    {
      whatsapp_campaign_id: id,
      campaign: {
        id: id,
        name: name,
        status: status,
        template: whatsapp_template&.name
      },
      name: name,
      status: status,
      requested_recipients: requested_recipients,
      total_recipients: total_recipients,
      sent_count: sent_count,
      delivered_count: delivered_count,
      read_count: read_count,
      failed_count: failed_count,
      replied_count: replied_count
    }
  end

  def sender_number
    whatsapp_sender_number || WhatsappSenderNumber.default_for_campaign(tenant)
  end

  def delivery_rate
    percent(delivered_count, sent_count)
  end

  def read_rate
    percent(read_count, sent_count)
  end

  def reply_rate
    percent(replied_count, sent_count)
  end

  def failure_rate
    percent(failed_count, total_recipients)
  end

  def attended_count
    converted = campaign_recipients.where(conversion_status: "converted").count
    return converted if converted.positive?

    campaign_messages.where(status: "replied").where.not(lead_id: nil).count
  end

  def unattended_count
    [replied_count.to_i - attended_count.to_i, 0].max
  end

  def response_decisions
    value = self[:response_decisions]
    value.is_a?(Hash) ? value.with_indifferent_access : {}.with_indifferent_access
  end

  def template_buttons
    whatsapp_template&.interactive_buttons || []
  end

  def response_decision_rows
    configured = response_decisions.dig(:buttons)
    configured = configured.values if configured.is_a?(Hash)
    configured_by_key = Array(configured).each_with_object({}) do |row, memo|
      attrs = row.respond_to?(:to_unsafe_h) ? row.to_unsafe_h : row.to_h
      memo[attrs["key"].to_s] = attrs.with_indifferent_access
    end

    template_buttons.map do |button|
      decision = configured_by_key[button["key"].to_s] || {}
      action = decision[:action].presence || default_response_action(button)
      button.merge(
        "action" => action,
        "action_label" => RESPONSE_ACTIONS.fetch(action.to_s, RESPONSE_ACTIONS["ignore"]),
        "message" => decision[:message].to_s,
        "distribution_rule_id" => decision[:distribution_rule_id].presence
      )
    end
  end

  def response_decision_for(button_text: nil, button_payload: nil)
    text = button_text.to_s.strip
    payload = button_payload.to_s.strip
    row = response_decision_rows.find do |item|
      item["text"].to_s.casecmp?(text) || (payload.present? && item["key"].to_s == payload)
    end
    return {} unless row

    row.slice("key", "text", "kind", "kind_label", "source", "context", "action", "action_label", "message", "distribution_rule_id")
  end

  def automation_driven_response_decisions?
    automation_workflow&.active?
  end

  def button_response_counts
    campaign_messages
      .where.not(reply_button_text: [nil, ""])
      .group("LOWER(reply_button_text)")
      .count
  end

  def dynamic_response_cards
    counts = button_response_counts
    rows = response_decision_rows.map do |button|
      count = counts.fetch(button["text"].to_s.downcase, 0)
      {
        key: button["key"],
        label: button["text"],
        context: button["context"].presence || button["kind_label"],
        action: button["action"],
        action_label: button["action_label"],
        count: count,
        tone: response_action_tone(button["action"]),
        icon: response_action_icon(button["action"])
      }
    end

    other = campaign_messages.where(status: "replied").where(reply_button_text: [nil, ""]).count
    rows << {
      key: "other_text_responses",
      label: "Outras respostas",
      context: "Texto livre ou mídia",
      action: "ignore",
      action_label: "Analisar pela automação",
      count: other,
      tone: "cyan",
      icon: "bi-chat-dots"
    } if other.positive?
    rows
  end

  def estimated_cost(sent_unit: nil, failed_unit: nil)
    sent_price = sent_unit || sender_number&.cpl_sent_unit_price || 0.59.to_d
    failed_price = failed_unit || sender_number&.cpl_fla_unit_price || 0.12.to_d
    (sent_count.to_i * sent_price.to_d) + (failed_count.to_i * failed_price.to_d)
  end

  def estimated_cpl(sent_unit: nil, failed_unit: nil)
    return 0.to_d if attended_count.zero?

    estimated_cost(sent_unit:, failed_unit:) / attended_count
  end

  def emit_event!(event_name, lead: nil, payload: {})
    Automation::Dispatcher.dispatch(
      event_name,
      lead || campaign_messages.includes(:lead).where.not(lead_id: nil).first&.lead,
      source: "whatsapp_campaign",
      payload: metrics_payload.merge(payload).compact,
      idempotency_key: "#{event_name}:whatsapp_campaign:#{id}:#{payload[:whatsapp_campaign_message_id]}"
    )
  end

  private

  def set_defaults
    self.status ||= "draft"
    self.audience_filters = {} unless audience_filters.is_a?(Hash)
    self.audience_definition = {} unless audience_definition.is_a?(Hash)
    self.template_variables = {} unless template_variables.is_a?(Hash)
    self.response_decisions = {} unless response_decisions.is_a?(Hash)
    self.group_name = group_name.to_s.strip.presence
    self.whatsapp_sender_number ||= WhatsappSenderNumber.default_for_campaign(tenant || created_by&.tenant || Current.tenant)
    self.audience_mode = "filters" if audience_mode.blank?
  end

  def template_must_be_approved
    return if whatsapp_template&.approved?

    errors.add(:whatsapp_template, "precisa estar aprovado para disparo")
  end

  def associations_must_belong_to_tenant
    return if tenant_id.blank?

    if whatsapp_template && whatsapp_template.tenant_id != tenant_id
      errors.add(:whatsapp_template, "deve pertencer ao mesmo Tenant")
    end

    if whatsapp_sender_number && whatsapp_sender_number.tenant_id != tenant_id
      errors.add(:whatsapp_sender_number, "deve pertencer ao mesmo Tenant")
    end

    if automation_workflow && automation_workflow.tenant_id != tenant_id
      errors.add(:automation_workflow, "deve pertencer ao mesmo Tenant")
    end
  end

  def scheduled_at_must_be_future
    if scheduled_at.blank?
      errors.add(:scheduled_at, "precisa ser informado para agendar o disparo")
      return
    end

    return if scheduled_at.future?

    errors.add(:scheduled_at, "precisa estar no futuro")
  end

  def spreadsheet_requires_file_or_existing_attachment
    return unless audience_mode == "spreadsheet"
    return if audience_file.attached?

    errors.add(:audience_file, "precisa ser enviada para importar destinatários por planilha")
  end

  def response_decisions_must_be_complete
    response_decision_rows.each do |row|
      next unless row["action"] == "generate_lead"

      if row["distribution_rule_id"].blank?
        errors.add(:response_decisions, "precisa indicar a regra de distribuição para o botão #{row['text']}")
        next
      end

      unless tenant.distribution_rules.active.exists?(id: row["distribution_rule_id"])
        errors.add(:response_decisions, "usa uma regra de distribuição inválida para o botão #{row['text']}")
      end
    end
  end

  def percent(part, total)
    return 0 if total.to_i.zero?

    ((part.to_f / total.to_f) * 100).round(1)
  end

  def default_response_action(button)
    text = button["text"].to_s.downcase
    return "unsubscribe" if text.match?(/descadastr|sair|parar|stop/)
    return "mark_no_interest" if text.match?(/sem interesse|não tenho interesse|nao tenho interesse|bloquear/)
    return "generate_lead" if text.match?(/saiba|quero|interesse|atendimento|falar|mais/)

    "ignore"
  end

  def response_action_tone(action)
    {
      "generate_lead" => "green",
      "send_message" => "cyan",
      "create_task" => "purple",
      "mark_no_interest" => "blue",
      "unsubscribe" => "orange",
      "ignore" => "slate"
    }.fetch(action.to_s, "slate")
  end

  def response_action_icon(action)
    {
      "generate_lead" => "bi-person-check",
      "send_message" => "bi-chat-text",
      "create_task" => "bi-check2-square",
      "mark_no_interest" => "bi-person-x",
      "unsubscribe" => "bi-person-dash",
      "ignore" => "bi-archive"
    }.fetch(action.to_s, "bi-grid")
  end
end
