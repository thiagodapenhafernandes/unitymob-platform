module Webhooks
  class WhatsappController < ActionController::Base
    skip_forgery_protection

    # GET — verificação do webhook (challenge da Meta)
    def verify
      integration = WhatsappBusinessIntegration.find_by(webhook_verify_token: params["hub.verify_token"].to_s)
      expected = integration&.webhook_verify_token.presence

      if params["hub.mode"] == "subscribe" && expected.present? &&
         ActiveSupport::SecurityUtils.secure_compare(params["hub.verify_token"].to_s, expected)
        render plain: params["hub.challenge"]
      else
        head :forbidden
      end
    end

    # POST — recebimento de mensagens e status
    def receive
      raw_payload = request.raw_post.to_s
      payload = parse_payload(raw_payload)
      log_payload_summary(payload, raw_payload)

      Whatsapp::InboundProcessor.call(payload)
      head :ok
    rescue JSON::ParserError => e
      Rails.logger.warn("[wa webhook] JSON invalido: #{e.message}")
      head :ok
    rescue => e
      Rails.logger.error("[wa webhook] #{e.class}: #{e.message}")
      head :ok # responde 200 sempre para a Meta não entrar em retry-storm
    end

    private

    def parse_payload(raw_payload)
      return JSON.parse(raw_payload) if raw_payload.present?

      params.to_unsafe_h.except("controller", "action")
    end

    def log_payload_summary(payload, raw_payload)
      changes = Array(payload["entry"]).flat_map { |entry| Array(entry["changes"]) }
      summary = changes.map { |change| change_summary(change) }

      Rails.logger.info(
        "[wa webhook] recebido object=#{payload["object"].inspect} " \
        "entries=#{Array(payload["entry"]).size} changes=#{changes.size} " \
        "raw_bytes=#{raw_payload.bytesize} summary=#{summary.to_json}"
      )
    rescue => e
      Rails.logger.warn("[wa webhook] resumo indisponivel: #{e.message}")
    end

    def change_summary(change)
      value = change["value"] || {}
      message = Array(value["messages"]).first || {}
      status = Array(value["statuses"]).first || {}

      {
        field: change["field"],
        phone_number_id: value.dig("metadata", "phone_number_id"),
        display_phone_number: value.dig("metadata", "display_phone_number"),
        messages_count: Array(value["messages"]).size,
        statuses_count: Array(value["statuses"]).size,
        first_message: first_message_summary(message),
        first_status: first_status_summary(status)
      }.compact
    end

    def first_message_summary(message)
      return nil if message.blank?

      {
        id: message["id"],
        from: message["from"],
        from_user_id: message["from_user_id"],
        type: message["type"],
        button_text: message.dig("button", "text"),
        interactive_title: message.dig("interactive", "button_reply", "title") || message.dig("interactive", "list_reply", "title")
      }.compact
    end

    def first_status_summary(status)
      return nil if status.blank?

      {
        id: status["id"],
        status: status["status"],
        recipient_id: status["recipient_id"],
        recipient_user_id: status["recipient_user_id"],
        error_code: status.dig("errors", 0, "code"),
        error_title: status.dig("errors", 0, "title")
      }.compact
    end
  end
end
