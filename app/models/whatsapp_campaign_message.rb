class WhatsappCampaignMessage < ApplicationRecord
  STATUSES = %w[pending queued sent delivered read failed replied cancelled].freeze

  belongs_to :whatsapp_campaign, inverse_of: :campaign_messages
  belongs_to :whatsapp_campaign_recipient,
             class_name: "WhatsappCampaignRecipient",
             optional: true,
             inverse_of: :campaign_messages
  belongs_to :lead, optional: true
  belongs_to :whatsapp_message, optional: true

  validates :phone_number, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :external_message_id, uniqueness: true, allow_blank: true

  scope :pending_or_queued, -> { where(status: %w[pending queued]) }
  scope :failed, -> { where(status: "failed") }
  scope :ready_for_retry, -> {
    where(status: "failed")
      .where("retry_count < 3")
      .where("next_retry_at IS NULL OR next_retry_at <= ?", Time.current)
  }

  STATUSES.each do |value|
    define_method("#{value}?") { status == value }
  end

  def queue!
    update!(status: "queued", queued_at: Time.current)
  end

  def mark_sent!(message_id:, whatsapp_message: nil)
    return if sent? || delivered? || read? || replied?

    update!(
      status: "sent",
      external_message_id: message_id,
      whatsapp_message: whatsapp_message,
      sent_at: Time.current,
      failure_reason: nil
    )
    refresh_campaign_and_emit!("whatsapp_campaign_message_sent")
  end

  def mark_accepted_by_meta!(message_id:, whatsapp_message: nil, at: Time.current)
    return if sent? || delivered? || read? || replied?

    update!(
      status: "sent",
      external_message_id: message_id.presence || external_message_id,
      whatsapp_message: whatsapp_message || self.whatsapp_message,
      sent_at: at,
      failure_reason: nil
    )
    refresh_campaign_and_emit!("whatsapp_campaign_message_sent")
  end

  def mark_delivered!(at: Time.current)
    return if read? || replied?

    update!(status: "delivered", delivered_at: at)
    refresh_campaign_and_emit!("whatsapp_campaign_message_delivered")
  end

  def mark_read!(at: Time.current)
    return if replied?

    update!(status: "read", read_at: at)
    refresh_campaign_and_emit!("whatsapp_campaign_message_read")
  end

  def mark_replied!(at: Time.current, inbound_message: nil, raw_payload: nil)
    reply_attrs = reply_attributes(inbound_message, raw_payload)
    update!(reply_attrs.merge(status: "replied", replied_at: at))
    apply_response_decision!
    refresh_campaign_and_emit!(
      "whatsapp_campaign_message_replied",
      payload: inbound_payload(inbound_message).merge(reply_attrs.slice(:reply_type, :reply_body, :reply_button_text, :reply_button_payload, :reply_payload)).compact
    )
  end

  def mark_failed!(reason)
    next_retry = retry_count.to_i < 2 ? (2**retry_count.to_i).minutes.from_now : nil
    update!(
      status: "failed",
      failed_at: Time.current,
      failure_reason: reason.to_s.truncate(500),
      retry_count: retry_count.to_i + 1,
      next_retry_at: next_retry
    )
    refresh_campaign_and_emit!("whatsapp_campaign_message_failed", payload: { error: failure_reason })
  end

  def payload
    {
      whatsapp_campaign_message_id: id,
      whatsapp_campaign_id: whatsapp_campaign_id,
      whatsapp_campaign_recipient_id: whatsapp_campaign_recipient_id,
      lead_id: lead_id,
      phone_number: phone_number,
      external_message_id: external_message_id,
      status: status,
      failure_reason: failure_reason,
      recipient: recipient_payload
    }.compact
  end

  def display_name
    lead&.display_name.presence || whatsapp_campaign_recipient&.display_name.presence || phone_number
  end

  def status_label
    {
      "pending" => "Pendente",
      "queued" => "Na fila",
      "sent" => "Aceita pela Meta",
      "delivered" => "Entregue",
      "read" => "Lida",
      "failed" => "Falhou",
      "replied" => "Respondida",
      "cancelled" => "Cancelada"
    }.fetch(status.to_s, status.to_s.humanize)
  end

  private

  def refresh_campaign_and_emit!(event_name, payload: {})
    whatsapp_campaign.refresh_counters!
    whatsapp_campaign.emit_event!(event_name, lead: lead, payload: self.payload.merge(payload))
  end

  def inbound_payload(inbound_message)
    return {} unless inbound_message

    decision = whatsapp_campaign.response_decision_for(
      button_text: reply_button_text.presence || inbound_message.body,
      button_payload: reply_button_payload
    )

    {
      inbound_whatsapp_message_id: inbound_message.id,
      whatsapp_message_id: inbound_message.id,
      button_text: reply_button_text.presence,
      button_payload: reply_button_payload.presence,
      message_body: reply_body.presence || inbound_message.body,
      reply_type: reply_type,
      response_decision: decision.presence
    }
  end

  def reply_attributes(inbound_message, raw_payload)
    raw = raw_payload.is_a?(Hash) ? raw_payload.with_indifferent_access : {}.with_indifferent_access
    type = raw[:type].presence || inbound_message&.msg_type
    button_text =
      raw.dig(:button, :text).presence ||
      raw.dig(:interactive, :button_reply, :title).presence ||
      raw.dig(:interactive, :list_reply, :title).presence
    button_payload =
      raw.dig(:button, :payload).presence ||
      raw.dig(:button, :id).presence ||
      raw.dig(:interactive, :button_reply, :id).presence ||
      raw.dig(:interactive, :list_reply, :id).presence
    body = inbound_message&.body.to_s

    {
      reply_type: type.to_s.presence,
      reply_body: body.presence,
      reply_button_text: button_text.to_s.strip.presence,
      reply_button_payload: button_payload.to_s.strip.presence,
      reply_payload: compact_reply_payload(raw)
    }.compact
  end

  def compact_reply_payload(raw)
    return {} if raw.blank?

    {
      id: raw[:id],
      from: raw[:from],
      from_user_id: raw[:from_user_id],
      type: raw[:type],
      text: raw.dig(:text, :body),
      button: raw[:button],
      interactive: raw[:interactive]
    }.compact
  end

  def apply_response_decision!
    decision = whatsapp_campaign.response_decision_for(
      button_text: reply_button_text.presence || reply_body,
      button_payload: reply_button_payload
    ).with_indifferent_access
    action = decision[:action].to_s
    recipient = whatsapp_campaign_recipient

    case action
    when "generate_lead"
      return if lead_id.present?
      return unless recipient

      distribution_rule = DistributionRule.active.find_by(id: decision[:distribution_rule_id])
      created_lead = recipient.convert_to_lead!(distribution_rule: distribution_rule)
      update_column(:lead_id, created_lead.id)
      LeadActivity.log!(
        lead: created_lead,
        kind: "whatsapp_campaign_conversion",
        metadata: {
          whatsapp_campaign_id: whatsapp_campaign_id,
          whatsapp_campaign_message_id: id,
          button_text: reply_button_text,
          distribution_rule_id: distribution_rule&.id,
          decision: action
        }.compact
      )
    when "mark_no_interest"
      recipient&.mark_no_interest!
    when "unsubscribe"
      recipient&.unsubscribe!
    when "ignore"
      recipient&.update!(conversion_status: "ignored") if recipient&.conversion_status == "pending"
    end
  end

  def recipient_payload
    recipient = whatsapp_campaign_recipient
    return if recipient.blank?

    {
      id: recipient.id,
      name: recipient.display_name,
      phone: recipient.display_phone,
      email: recipient.display_email,
      origin: recipient.origin,
      status: recipient.status,
      tags: recipient.tag_list,
      conversion_status: recipient.conversion_status
    }.compact
  end
end
