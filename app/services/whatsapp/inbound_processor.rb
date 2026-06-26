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

      if conversation.lead_id.blank?
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
