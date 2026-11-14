class WhatsappCampaignInteraction < ApplicationRecord
  include TenantScoped

  OUTCOME_LABELS = {
    "forwarded" => "Encaminhados à fila", "attendance_started" => "Atendimentos aceitos",
    "task_created" => "Com tarefa criada", "no_interest" => "Sem interesse",
    "unsubscribed" => "Descadastrados", "no_attendance" => "Sem atendimento definido",
    "recorded" => "Apenas registrados"
  }.freeze

  belongs_to :whatsapp_campaign
  belongs_to :whatsapp_campaign_message
  belongs_to :inbound_whatsapp_message, class_name: "WhatsappMessage", optional: true
  belongs_to :source_response, class_name: name, optional: true

  validates :event_key, :recipient_key, :occurred_at, presence: true
  validates :kind, inclusion: {in: %w[response action]}
  validate :consistent_context

  scope :responses, -> { where(kind: "response") }
  scope :actions, -> { where(kind: "action") }

  def readonly?
    persisted?
  end

  def self.recipient_key(message)
    Digest::SHA256.hexdigest(message.phone_number.to_s.gsub(/\D/, ""))
  end

  def self.record_response!(message:, inbound: nil, attributes:, at:, legacy: false)
    identity = inbound&.wa_message_id.presence || inbound&.id || attributes.dig(:reply_payload, :id) || attributes.dig(:reply_payload, "id")
    key = identity.present? ? "reply:#{message.id}:#{identity}" : "legacy:#{message.id}"
    decision = legacy ? {} : message.whatsapp_campaign.response_decision_for(
      button_text: attributes[:reply_button_text].presence || attributes[:reply_body], button_payload: attributes[:reply_button_payload])
    button_text = attributes[:reply_button_text]
    if button_text.blank? && %w[button interactive].include?(attributes[:reply_type].to_s)
      button_text = decision["text"].presence || ("Botão sem título" if attributes[:reply_button_payload].present?)
    end
    create_or_find_by!(tenant: message.tenant, event_key: key) do |record|
      record.assign_attributes(whatsapp_campaign: message.whatsapp_campaign, whatsapp_campaign_message: message,
        inbound_whatsapp_message: inbound, recipient_key: recipient_key(message), kind: "response", occurred_at: at,
        button_key: decision["key"].presence || attributes[:reply_button_payload].presence,
        button_text: button_text, body: attributes[:reply_body], action_key: decision["action"],
        action_label: decision["action_label"], metadata: {legacy_snapshot: legacy, inbound_external_id: identity}.compact)
    end
  end

  def self.record_action!(response:, action_key:, label:, outcome:, metadata: {})
    return unless response&.kind == "response"
    metadata = metadata.to_h.deep_stringify_keys
    key = Digest::SHA256.hexdigest([response.id, action_key, outcome, metadata.sort.to_json].join(":"))
    create_or_find_by!(tenant: response.tenant, event_key: "action:#{key}") do |record|
      record.assign_attributes(whatsapp_campaign: response.whatsapp_campaign,
        whatsapp_campaign_message: response.whatsapp_campaign_message, source_response: response,
        recipient_key: response.recipient_key, kind: "action", action_key: action_key, action_label: label,
        outcome: outcome, metadata: metadata, occurred_at: Time.current)
    end
  end

  def outcome_label
    OUTCOME_LABELS[outcome] || action_label.presence || action_key.to_s.humanize
  end

  private

  def consistent_context
    records = [whatsapp_campaign, whatsapp_campaign_message, inbound_whatsapp_message, source_response].compact
    errors.add(:base, "Interação fora da conta") if records.any? { |record| record.tenant_id != tenant_id }
    if whatsapp_campaign_message && whatsapp_campaign_message.whatsapp_campaign_id != whatsapp_campaign_id
      errors.add(:base, "Mensagem de outra campanha")
    end
    if source_response && (source_response.whatsapp_campaign_message_id != whatsapp_campaign_message_id || source_response.kind != "response")
      errors.add(:base, "Resposta de outro contexto")
    end
    if inbound_whatsapp_message && whatsapp_campaign_message
      conversation = inbound_whatsapp_message.whatsapp_conversation
      message = whatsapp_campaign_message
      same_phone = conversation.contact_phone.to_s.gsub(/\D/, "") == message.phone_number.to_s.gsub(/\D/, "")
      same_lead = conversation.lead_id.present? && conversation.lead_id == message.lead_id
      errors.add(:base, "Resposta de outro destinatário") unless same_phone || same_lead
      sender_id = whatsapp_campaign.whatsapp_sender_number_id
      if conversation.whatsapp_sender_number_id.present? && sender_id.present? && conversation.whatsapp_sender_number_id != sender_id
        errors.add(:base, "Resposta de outro número remetente")
      end
    end
    if inbound_whatsapp_message && !inbound_whatsapp_message.inbound?
      errors.add(:base, "A interação exige mensagem recebida")
    end
  end
end
