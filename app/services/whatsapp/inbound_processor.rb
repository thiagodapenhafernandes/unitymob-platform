module Whatsapp
  # Processa o payload do webhook da WhatsApp Cloud API:
  # - mensagens recebidas -> cria/atualiza conversa + mensagem + vincula lead + timeline
  # - status (sent/delivered/read) -> atualiza a mensagem enviada
  class InboundProcessor
    def self.call(payload)
      new(payload).call
    end

    def initialize(payload)
      @payload = payload.is_a?(Hash) ? payload : {}
    end

    def call
      Array(@payload["entry"]).each do |entry|
        Array(entry["changes"]).each do |change|
          value = change["value"] || {}
          capture_bsuid_payload(change) # Fase 0: visibilidade dos webhooks reais

          # Webhook dedicado de mudança de BSUID (field "user_id_update").
          if change["field"].to_s == "user_id_update" || value["user_id_update"].present?
            handle_user_id_update(value)
            next
          end

          if change["field"].to_s == "message_template_status_update"
            handle_template_status_update(value)
            next
          end

          contacts = index_contacts(value["contacts"])
          Array(value["messages"]).each { |msg| handle_inbound(msg, contacts) }
          Array(value["statuses"]).each { |st| handle_status(st) }
        end
      end
      true
    end

    private

    # Indexa contatos por telefone (wa_id) E por BSUID (user_id), guardando o nome,
    # para enriquecer a conversa independentemente da identidade do remetente.
    def index_contacts(contacts)
      Array(contacts).each_with_object({}) do |c, acc|
        info = {
          name:  c.dig("profile", "name").presence || c.dig("profile", "username").presence,
          wa_id: c["wa_id"].presence,
          bsuid: c["user_id"].presence
        }
        acc[c["wa_id"].to_s]   = info if c["wa_id"].present?
        acc[c["user_id"].to_s] = info if c["user_id"].present?
      end
    end

    def handle_inbound(msg, contacts)
      return if WhatsappMessage.exists?(wa_message_id: msg["id"]) # dedup pelo id da mensagem
      return if msg["type"].to_s == "system" # eventos de sistema (ex.: troca de número) não são mensagens

      # Campos oficiais da Meta: `from` (telefone, pode faltar quando o número está
      # escondido) e `from_user_id` (BSUID). Aceita qualquer um dos dois.
      phone = msg["from"].presence
      bsuid = msg["from_user_id"].presence
      return if phone.blank? && bsuid.blank? # nenhuma identidade utilizável

      contact = contacts[phone.to_s] || contacts[bsuid.to_s] || {}
      name = contact[:name]

      conversation = find_or_create_conversation(phone: phone, bsuid: bsuid, name: name)
      type = msg["type"].to_s
      body = extract_body(msg, type)

      message = conversation.messages.create!(
        direction: "inbound",
        wa_message_id: msg["id"],
        msg_type: type.presence || "text",
        body: body,
        status: "delivered",
        delivered_at: Time.current
      )

      conversation.update_columns(unread_count: conversation.unread_count.to_i + 1, updated_at: Time.current)
      conversation.touch_last_message!(message)

      campaign_message = mark_campaign_reply!(conversation, message, raw_message: msg)

      if conversation.lead_id
        meta = { body: message.preview, phone: phone, bsuid: bsuid }.compact
        LeadActivity.log!(lead: conversation.lead, kind: "whatsapp_in", metadata: meta)
        Automation::Dispatcher.dispatch(
          :whatsapp_received,
          conversation.lead,
          source: "whatsapp",
          payload: { whatsapp_message_id: message.id, wa_message_id: message.wa_message_id, phone: phone, bsuid: bsuid }.compact,
          idempotency_key: "whatsapp_received:#{message.id}"
        )
      end
    end

    # BSUID mudou (webhook user_id_update): re-vincula conversa/lead do BSUID antigo
    # para o novo. Estrutura oficial: array com { user_id: { previous, current } }.
    def handle_user_id_update(value)
      Array(value["user_id_update"]).each do |entry|
        old_id = entry.dig("user_id", "previous").presence
        new_id = entry.dig("user_id", "current").presence
        next if old_id.blank? || new_id.blank?

        WhatsappConversation.where(business_scoped_user_id: old_id)
                            .update_all(business_scoped_user_id: new_id, updated_at: Time.current)
        Lead.where(business_scoped_user_id: old_id)
            .update_all(business_scoped_user_id: new_id, updated_at: Time.current)
        Rails.logger.info("[wa-bsuid] user_id_update #{old_id} -> #{new_id}")
      end
    end

    # Fase 0: registra a presença de BSUID nos webhooks reais (sem corpo de mensagem).
    def capture_bsuid_payload(change)
      value = change["value"]
      contacts = Array(value && value["contacts"])
      has_bsuid = contacts.any? { |c| c["user_id"].present? }
      return unless has_bsuid || change["field"].to_s == "user_id_update" || (value && value["user_id_update"].present?)

      summary = {
        field: change["field"],
        contacts: contacts.map { |c| { wa_id: c["wa_id"], user_id: c["user_id"] } },
        user_id_update: value && value["user_id_update"]
      }.compact
      Rails.logger.info("[wa-bsuid] #{summary.to_json}")
    rescue => e
      Rails.logger.warn("[wa-bsuid] capture falhou: #{e.message}")
    end

    def handle_template_status_update(value)
      template_id = value["message_template_id"].presence&.to_s
      template_name = value["message_template_name"].presence
      language = value["message_template_language"].presence || "pt_BR"
      event = value["event"].presence&.to_s&.upcase
      reason = value["reason"].presence

      template = if template_id.present?
                   WhatsappTemplate.find_by(meta_id: template_id)
                 end
      template ||= WhatsappTemplate.find_by(name: template_name, language: language) if template_name.present?

      unless template
        Rails.logger.warn(
          "[wa-template-status] template nao encontrado " \
          "meta_id=#{template_id.inspect} name=#{template_name.inspect} language=#{language.inspect} event=#{event.inspect}"
        )
        return
      end

      attrs = { updated_at: Time.current }
      attrs[:status] = event if event.present? && event != "NONE"
      attrs[:submission_error] = template_submission_error(event, reason)
      template.update_columns(attrs)

      Rails.logger.info(
        "[wa-template-status] template=#{template.name.inspect} meta_id=#{template.meta_id.inspect} " \
        "status=#{template.status.inspect} reason=#{reason.inspect}"
      )
    end

    def template_submission_error(event, reason)
      return nil if event.to_s == "APPROVED"
      return reason if reason.present?
      return nil if event.blank? || event == "NONE" || event == "PENDING"

      "Status retornado pela Meta: #{event}"
    end

    def handle_status(status)
      message = WhatsappMessage.find_by(wa_message_id: status["id"])
      return unless message

      state = status["status"].to_s
      attrs = { status: state }
      attrs[:recipient_user_id] = status["recipient_user_id"] if status["recipient_user_id"].present?
      attrs[:delivered_at] = Time.zone.at(status["timestamp"].to_i) if state == "delivered" && status["timestamp"].present?
      attrs[:read_at] = Time.zone.at(status["timestamp"].to_i) if state == "read" && status["timestamp"].present?
      attrs[:error_message] = status.dig("errors", 0, "title") if state == "failed"
      message.update_columns(attrs.merge(updated_at: Time.current))

      campaign_message = WhatsappCampaignMessage.find_by(external_message_id: status["id"])
      return unless campaign_message

      occurred_at = status["timestamp"].present? ? Time.zone.at(status["timestamp"].to_i) : Time.current
      case state
      when "sent"
        campaign_message.mark_accepted_by_meta!(
          message_id: status["id"],
          whatsapp_message: message,
          at: occurred_at
        )
      when "delivered"
        campaign_message.mark_delivered!(at: occurred_at)
      when "read"
        campaign_message.mark_read!(at: occurred_at)
      when "failed"
        campaign_message.mark_failed!(attrs[:error_message].presence || "Falha informada pela Meta")
      end
    end

    def mark_campaign_reply!(conversation, inbound_message, raw_message:)
      campaign_message = nil
      if conversation.lead_id.present?
        campaign_message = WhatsappCampaignMessage
          .joins(:whatsapp_campaign)
          .where(lead_id: conversation.lead_id)
          .where(status: %w[sent delivered read])
          .where(whatsapp_campaigns: { status: %w[processing completed] })
          .order(sent_at: :desc, id: :desc)
          .first
      end
      campaign_message ||= campaign_reply_candidate(conversation.contact_phone)

      return unless campaign_message

      campaign_message.mark_replied!(
        at: inbound_message.created_at,
        inbound_message: inbound_message,
        raw_payload: raw_message
      )
      link_conversation_to_campaign_lead!(conversation, campaign_message)
      campaign_message
    end

    def link_conversation_to_campaign_lead!(conversation, campaign_message)
      campaign_message.reload
      lead = campaign_message.lead
      return unless lead
      return if conversation.lead_id == lead.id

      conversation.update_column(:lead_id, lead.id)
    end

    def normalize_phone(value)
      digits = value.to_s.gsub(/\D/, "")
      return "" if digits.blank?

      digits.length <= 11 ? "55#{digits}" : digits
    end

    def campaign_reply_candidate(phone)
      normalized = normalize_phone(phone)
      return if normalized.blank?

      WhatsappCampaignMessage
        .left_joins(:whatsapp_campaign_recipient)
        .joins(:whatsapp_campaign)
        .where(status: %w[sent delivered read])
        .where(whatsapp_campaigns: { status: %w[processing completed] })
        .where(
          "whatsapp_campaign_messages.phone_number = :phone OR whatsapp_campaign_recipients.phone_number = :phone",
          phone: normalized
        )
        .order(sent_at: :desc, id: :desc)
        .first
    end

    def extract_body(msg, type)
      case type
      when "text" then msg.dig("text", "body")
      when "button" then msg.dig("button", "text")
      when "interactive" then msg.dig("interactive", "button_reply", "title") || msg.dig("interactive", "list_reply", "title")
      when "image", "document", "audio", "video" then msg.dig(type, "caption")
      else nil
      end.to_s
    end

    def find_or_create_conversation(phone:, bsuid:, name:)
      conversation =
        (phone.present? && WhatsappConversation.find_by(contact_phone: phone)) ||
        (bsuid.present? && WhatsappConversation.find_by(business_scoped_user_id: bsuid)) ||
        WhatsappConversation.new

      # Backfill: completa a identidade que faltava (mescla telefone + BSUID).
      conversation.contact_phone = phone if phone.present? && conversation.contact_phone.blank?
      conversation.business_scoped_user_id = bsuid if bsuid.present? && conversation.business_scoped_user_id.blank?
      conversation.contact_name = name if name.present? && conversation.contact_name.blank?
      conversation.status = "open"

      if conversation.lead_id.blank? && campaign_reply_candidate(phone).blank?
        conversation.lead = link_or_create_lead(phone: phone, bsuid: bsuid, name: name)
      end

      conversation.save!
      conversation
    end

    def link_or_create_lead(phone:, bsuid:, name:)
      # 1) Por BSUID (identidade estável).
      if bsuid.present?
        lead = Lead.find_by(business_scoped_user_id: bsuid)
        return lead if lead
      end

      # 2) Por telefone (últimos 8 dígitos), e backfill do BSUID quando o conhecemos.
      if phone.present?
        tail = phone.gsub(/\D/, "").last(8)
        lead = Lead.where("regexp_replace(coalesce(phone, ''), '\\D', '', 'g') LIKE ?", "%#{tail}").first
        if lead
          lead.update_column(:business_scoped_user_id, bsuid) if bsuid.present? && lead.business_scoped_user_id.blank?
          return lead
        end
      end

      Lead.create!(
        name: name.presence || "Contato WhatsApp #{phone || bsuid}",
        phone: phone,
        business_scoped_user_id: bsuid,
        origin: "whatsapp",
        status: Lead.default_status
      )
    rescue => e
      Rails.logger.warn("[wa inbound] lead link failed: #{e.message}")
      nil
    end
  end
end
