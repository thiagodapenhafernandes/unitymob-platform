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
          contacts = index_contacts(value["contacts"])
          Array(value["messages"]).each { |msg| handle_inbound(msg, contacts) }
          Array(value["statuses"]).each { |st| handle_status(st) }
        end
      end
      true
    end

    private

    def index_contacts(contacts)
      Array(contacts).each_with_object({}) do |c, acc|
        acc[c["wa_id"].to_s] = c.dig("profile", "name")
      end
    end

    def handle_inbound(msg, contacts)
      wa_id = msg["from"].to_s
      return if wa_id.blank?
      return if WhatsappMessage.exists?(wa_message_id: msg["id"]) # dedup

      conversation = find_or_create_conversation(wa_id, contacts[wa_id])
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
        LeadActivity.log!(lead: conversation.lead, kind: "whatsapp_in", metadata: { body: message.preview, phone: wa_id })
        Automation::Dispatcher.dispatch(
          :whatsapp_received,
          conversation.lead,
          source: "whatsapp",
          payload: { whatsapp_message_id: message.id, wa_message_id: message.wa_message_id, phone: wa_id },
          idempotency_key: "whatsapp_received:#{message.id}"
        )
      end
    end

    def handle_status(status)
      message = WhatsappMessage.find_by(wa_message_id: status["id"])
      return unless message

      state = status["status"].to_s
      attrs = { status: state }
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

    def find_or_create_conversation(wa_id, name)
      conversation = WhatsappConversation.find_or_initialize_by(contact_phone: wa_id)
      conversation.contact_name = name if name.present? && conversation.contact_name.blank?
      conversation.status = "open"

      if conversation.lead_id.blank?
        conversation.lead = link_or_create_lead(wa_id, name)
      end

      conversation.save!
      conversation
    end

    def link_or_create_lead(wa_id, name)
      digits = wa_id.gsub(/\D/, "")
      tail = digits.last(8)
      existing = Lead.where("regexp_replace(coalesce(phone, ''), '\\D', '', 'g') LIKE ?", "%#{tail}").first
      return existing if existing

      Lead.create!(
        name: name.presence || "Contato WhatsApp #{wa_id}",
        phone: wa_id,
        origin: "whatsapp",
        status: Lead.default_status
      )
    rescue => e
      Rails.logger.warn("[wa inbound] lead link failed: #{e.message}")
      nil
    end
  end
end
