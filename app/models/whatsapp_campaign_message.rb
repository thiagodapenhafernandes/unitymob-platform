class WhatsappCampaignMessage < ApplicationRecord
  include TenantScoped

  STATUSES = %w[pending queued sent delivered read failed replied cancelled].freeze
  DELIVERY_UNCONFIRMED_STATUS = "delivery_unconfirmed".freeze
  DELIVERY_STATUS_STALE_AFTER = 5.minutes
  STATUS_LABELS = {
    "pending" => "Pendente",
    "queued" => "Na fila",
    "sent" => "Enviado",
    "delivered" => "Entregue",
    "read" => "Lido",
    "failed" => "Falha",
    "replied" => "Respondido",
    "cancelled" => "Não entregue"
  }.freeze
  VIRTUAL_STATUS_LABELS = {
    DELIVERY_UNCONFIRMED_STATUS => "Sem retorno de entrega"
  }.freeze
  # Colunas cumulativas de contadores da campanha às quais cada status pertence
  # (espelha a semântica do recount em WhatsappCampaign#refresh_counters!:
  # sent_count inclui delivered/read/replied; delivered_count inclui read/replied...).
  CAMPAIGN_COUNTER_COLUMNS = {
    "sent" => %i[sent_count],
    "delivered" => %i[sent_count delivered_count],
    "read" => %i[sent_count delivered_count read_count],
    "replied" => %i[sent_count delivered_count read_count replied_count],
    "failed" => %i[failed_count],
    "cancelled" => %i[failed_count]
  }.freeze
  FAILURE_CODE_PATTERNS = [
    /c[oó]digo[:\s]+(\d{5,6})/i,
    /codigo[:\s]+(\d{5,6})/i,
    /code[:\s]+(\d{5,6})/i,
    /\(#(\d{5,6})\)/,
    /\b(\d{5,6})\b/
  ].freeze
  FAILURE_REASON_DEFINITIONS = {
    "132015" => {
      group_key: "code:132015",
      label: "Template pausado pela Meta por baixa qualidade",
      technical: "código 132015",
      severity: "error",
      guidance: "Revise o status e a qualidade do template antes de retomar o disparo."
    },
    "132001" => {
      group_key: "code:132001",
      label: "Template sem tradução disponível para o idioma solicitado",
      technical: "código 132001",
      severity: "error",
      guidance: "Confirme o idioma aprovado do template antes de reprocessar."
    },
    "132012" => {
      group_key: "code:132012",
      label: "Formato enviado não corresponde ao template aprovado",
      technical: "código 132012",
      severity: "error",
      guidance: "Revise variáveis, mídia, botões e estrutura do template antes de reprocessar."
    },
    "131049" => {
      group_key: "code:131049",
      label: "Envio limitado pela Meta para manter engajamento saudável",
      technical: "código 131049",
      severity: "warning",
      guidance: "Aguarde uma janela posterior; retentar agora costuma repetir a restrição."
    },
    "131026" => {
      group_key: "code:131026",
      label: "Número indisponível no WhatsApp ou sem permissão de contato (opt-in)",
      technical: "código 131026",
      severity: "warning",
      guidance: "Valide o telefone e a permissão de contato antes de reenviar."
    },
    "130472" => {
      group_key: "code:130472",
      label: "Número do destinatário em experimento da Meta/WhatsApp",
      technical: "código 130472",
      severity: "warning",
      guidance: "Trate como restrição temporária da Meta; reprocessar em massa pode não mudar o resultado."
    }
  }.freeze

  belongs_to :whatsapp_campaign, inverse_of: :campaign_messages
  belongs_to :whatsapp_campaign_recipient,
             class_name: "WhatsappCampaignRecipient",
             optional: true,
             inverse_of: :campaign_messages
  belongs_to :lead, optional: true
  belongs_to :whatsapp_message, optional: true

  validates :phone_number, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :external_message_id, uniqueness: { scope: :tenant_id }, allow_blank: true

  scope :pending_or_queued, -> { where(status: %w[pending queued]) }
  scope :failed, -> { where(status: "failed") }
  scope :delivery_unconfirmed, -> {
    where(status: "sent")
      .where("COALESCE(sent_at, updated_at) <= ?", DELIVERY_STATUS_STALE_AFTER.ago)
  }
  scope :ready_for_retry, -> {
    where(status: "failed")
      .where("retry_count < 3")
      .where("next_retry_at IS NULL OR next_retry_at <= ?", Time.current)
  }

  # Contadores da campanha por transição de status (O(1) por evento) no lugar
  # do recount da campanha inteira a cada mensagem; o recount completo fica
  # para os marcos (conclusão, pausa, retry/cancel em massa e sweep periódico).
  after_update :apply_campaign_counter_delta, if: :saved_change_to_status?

  STATUSES.each do |value|
    define_method("#{value}?") { status == value }
  end

  def self.status_options
    STATUSES.map { |value| [STATUS_LABELS.fetch(value), value] }
      .insert(3, [VIRTUAL_STATUS_LABELS.fetch(DELIVERY_UNCONFIRMED_STATUS), DELIVERY_UNCONFIRMED_STATUS])
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
    apply_response_decision! unless whatsapp_campaign.automation_driven_response_decisions?
    refresh_campaign_and_emit!(
      "whatsapp_campaign_message_replied",
      payload: inbound_payload(inbound_message).merge(reply_attrs.slice(:reply_type, :reply_body, :reply_button_text, :reply_button_payload, :reply_payload)).compact
    )
  end

  # source :meta (default) = webhook de status da Meta, autoritativo: pode
  # regredir uma mensagem aceita para failed (falha real de entrega).
  # source :local = sender/pipeline: NUNCA regride mensagem já aceita — a
  # marcação failed habilitaria reenvio (automático/manual) e dupla entrega.
  def mark_failed!(reason, source: :meta)
    return if source == :local && (sent? || delivered? || read? || replied?)

    next_retry = calculate_next_retry_at(reason)
    update!(
      status: "failed",
      failed_at: Time.current,
      failure_reason: reason.to_s.truncate(500),
      retry_count: retry_count.to_i + 1,
      next_retry_at: next_retry
    )
    refresh_campaign_and_emit!("whatsapp_campaign_message_failed", payload: { error: failure_reason })
  end

  def mark_cancelled!(reason)
    update!(
      status: "cancelled",
      failed_at: Time.current,
      failure_reason: reason.to_s.truncate(500)
    )
    refresh_campaign_and_emit!("whatsapp_campaign_message_cancelled", payload: { error: failure_reason })
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
    STATUS_LABELS.fetch(status.to_s, status.to_s.humanize)
  end

  def display_status_label
    delivery_unconfirmed? ? VIRTUAL_STATUS_LABELS.fetch(DELIVERY_UNCONFIRMED_STATUS) : status_label
  end

  def display_status_key
    delivery_unconfirmed? ? DELIVERY_UNCONFIRMED_STATUS : status
  end

  def delivery_unconfirmed?(now = Time.current)
    return false unless sent?

    reference_time = sent_at || updated_at
    reference_time.present? && reference_time <= now - DELIVERY_STATUS_STALE_AFTER
  end

  def status_note
    return failure_reason if failure_reason.present?
    return "Aguardando webhook de entrega/leitura da Meta." if delivery_unconfirmed?

    "-"
  end

  def response_status_label
    return "Sem resposta" unless replied?

    reply_button_text.presence || reply_body.presence || "Resposta recebida"
  end

  def response_status_note
    return "Aguardando resposta do destinatário." unless replied?

    decision = response_decision
    return decision["action_label"] if decision["action_label"].present?

    reply_type.to_s == "button" ? "Botão do template" : "Texto livre ou mídia"
  end

  def response_status_key
    return "no_response" unless replied?

    response_decision["action"].presence || "replied"
  end

  def response_status_tone
    case response_status_key
    when "generate_lead" then "green"
    when "mark_no_interest" then "blue"
    when "unsubscribe" then "orange"
    when "ignore" then "gray"
    when "replied" then "cyan"
    else "gray"
    end
  end

  def response_decision
    return {} unless replied?

    whatsapp_campaign.response_decision_for(
      button_text: reply_button_text.presence || reply_body,
      button_payload: reply_button_payload
    )
  end

  def failure_reason_details
    self.class.normalize_failure_reason(failure_reason)
  end

  def self.extract_failure_code(reason)
    text = reason.to_s
    FAILURE_CODE_PATTERNS.each do |pattern|
      match = text.match(pattern)
      return match[1] if match
    end

    nil
  end

  def self.normalize_failure_reason(reason)
    text = reason.to_s.strip
    code = extract_failure_code(text)
    return FAILURE_REASON_DEFINITIONS.fetch(code).dup if FAILURE_REASON_DEFINITIONS.key?(code)

    if text.casecmp("cancelled_by_user").zero? || text.downcase.include?("cancelado manualmente")
      return {
        group_key: "cancelled_by_user",
        label: "Envio cancelado manualmente",
        technical: nil,
        severity: "warning",
        guidance: "Não é falha da Meta; revise se ainda faz sentido reenviar esse público."
      }
    end

    cleaned = cleanup_failure_reason(text)
    {
      group_key: cleaned.downcase.presence || "unknown",
      label: cleaned.presence || "Motivo não informado pela Meta",
      technical: code.present? ? "código #{code}" : nil,
      severity: "error",
      guidance: "Revise a integração, o template e o payload antes de reprocessar."
    }
  end

  def self.cleanup_failure_reason(reason)
    reason.to_s
      .gsub(/\s*\|\s*(c[oó]digo|codigo|code):?\s*\d{5,6}/i, "")
      .gsub(/\s*\(#?\d{5,6}\)/, "")
      .squish
  end

  private

  def calculate_next_retry_at(reason)
    code = self.class.extract_failure_code(reason)
    next_retry_count = retry_count.to_i + 1

    if code == "131049"
      case next_retry_count
      when 1 then 6.hours.from_now
      when 2 then 24.hours.from_now
      else nil
      end
    else
      case next_retry_count
      when 1 then 5.minutes.from_now
      when 2 then 15.minutes.from_now
      when 3 then 30.minutes.from_now
      else nil
      end
    end
  end

  def refresh_campaign_and_emit!(event_name, payload: {})
    # Contadores já foram ajustados via apply_campaign_counter_delta; o reload
    # (SELECT por PK) garante metrics_payload fresco no evento/broadcast.
    whatsapp_campaign.reload
    whatsapp_campaign.emit_event!(event_name, lead: lead, payload: self.payload.merge(payload))
  end

  def apply_campaign_counter_delta
    previous_status, new_status = saved_change_to_status
    previous_columns = CAMPAIGN_COUNTER_COLUMNS.fetch(previous_status.to_s, [])
    new_columns = CAMPAIGN_COUNTER_COLUMNS.fetch(new_status.to_s, [])
    deltas = {}
    (new_columns - previous_columns).each { |column| deltas[column] = 1 }
    (previous_columns - new_columns).each { |column| deltas[column] = -1 }
    return if deltas.empty?

    WhatsappCampaign.update_counters(whatsapp_campaign_id, deltas.merge(touch: true))
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
      sender_number = whatsapp_campaign.sender_number
      if sender_number
        WhatsappCampaignUnsubscribe.register!(
          sender_number: sender_number,
          phone: phone_number,
          contact_name: recipient&.display_name,
          campaign_message: self,
          campaign_recipient: recipient,
          inbound_message: inbound_whatsapp_message,
          metadata: {
            reply_button_text: reply_button_text,
            reply_button_payload: reply_button_payload
          }.compact
        )
      end
    when "ignore"
      recipient&.update!(conversion_status: "ignored") if recipient&.conversion_status == "pending"
    end
  end

  def inbound_whatsapp_message
    return nil if reply_payload.blank?

    tenant.whatsapp_messages.find_by(wa_message_id: reply_payload["id"])
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
