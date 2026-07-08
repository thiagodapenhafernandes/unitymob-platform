module Webhooks
  class WhatsappController < ActionController::Base
    include Webhooks::MetaSignature

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

    # POST — recebimento de mensagens e status. Valida a assinatura, enfileira
    # e responde 200 imediato: o processamento (mídia, campanha, lead) roda no
    # worker via Whatsapp::InboundWebhookJob, fora da thread do Puma.
    def receive
      raw_payload = request.raw_post.to_s

      unless valid_meta_signature?(raw_payload)
        Rails.logger.warn("[wa webhook] assinatura X-Hub-Signature-256 invalida; payload rejeitado")
        return head :forbidden
      end

      payload = parse_payload(raw_payload)
      log_payload_summary(payload, raw_payload)

      enqueue_payload(payload)
      head :ok
    rescue JSON::ParserError => e
      Rails.logger.warn("[wa webhook] JSON invalido: #{e.message}")
      head :ok
    rescue => e
      Rails.logger.error("[wa webhook] falha ao enfileirar processamento #{e.class}: #{e.message}\n#{Array(e.backtrace).first(10).join("\n")}")
      head :ok # responde 200 sempre para a Meta não entrar em retry-storm
    end

    private

    # O produto WhatsApp pode ter secret próprio (config do Admin do Sistema);
    # wa_app_secret já cai no ENV correspondente quando o campo está vazio.
    def meta_webhook_app_secret
      SystemNotificationSetting.instance.wa_app_secret
    rescue StandardError
      ENV["WHATSAPP_APP_SECRET"].presence || ENV["FACEBOOK_APP_SECRET"].presence
    end

    def parse_payload(raw_payload)
      return JSON.parse(raw_payload) if raw_payload.present?

      params.to_unsafe_h.except("controller", "action")
    end

    def enqueue_payload(payload)
      job = inbound_job_for(payload)
      return job.perform_later(payload) unless quiet_enqueue_logs?

      Rails.logger.silence(Logger::WARN) do
        job.perform_later(payload)
      end
    end

    def inbound_job_for(payload)
      return Whatsapp::InboundWebhookJob.set(queue: :whatsapp_statuses) if status_only_payload?(payload)

      Whatsapp::InboundWebhookJob
    end

    def quiet_enqueue_logs?
      Rails.env.development? &&
        ENV.fetch("WA_WEBHOOK_VERBOSE_ENQUEUE_LOGS", "0") != "1" &&
        Rails.logger.respond_to?(:silence)
    end

    def log_payload_summary(payload, raw_payload)
      return if status_only_payload?(payload) && !verbose_status_logs?

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

    def verbose_status_logs?
      ENV.fetch("WA_WEBHOOK_VERBOSE_STATUS_LOGS", "0") == "1"
    end

    def status_only_payload?(payload)
      changes = payload_changes(payload)
      changes.present? && changes.all? { |change| status_only_change?(change) }
    end

    def status_only_change?(change)
      value = change["value"] || {}

      Array(value["statuses"]).present? &&
        Array(value["messages"]).blank? &&
        change["field"].to_s != "message_template_status_update" &&
        value["user_id_update"].blank?
    end

    def payload_changes(payload)
      Array(payload["entry"]).flat_map { |entry| Array(entry["changes"]) }
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
        message_types: message_types(value),
        status_counts: status_counts(value),
        first_message: first_message_summary(message),
        first_status_error: first_status_error_summary(status)
      }.compact
    end

    def first_message_summary(message)
      return nil if message.blank?

      {
        id: message["id"],
        from: masked_identifier(message["from"]),
        from_user_id: masked_identifier(message["from_user_id"]),
        type: message["type"],
        button_text: message.dig("button", "text"),
        interactive_title: message.dig("interactive", "button_reply", "title") || message.dig("interactive", "list_reply", "title")
      }.compact
    end

    def masked_identifier(value)
      value = value.to_s
      return nil if value.blank?
      return "[FILTERED]" if value.length <= 4

      "*#{value.last(4)}"
    end

    def message_types(value)
      Array(value["messages"]).filter_map { |message| message["type"].presence }.tally.presence
    end

    def status_counts(value)
      Array(value["statuses"]).filter_map { |status| status["status"].presence }.tally.presence
    end

    def first_status_error_summary(status)
      return nil if status.blank?
      return nil if Array(status["errors"]).blank?

      {
        id: status["id"],
        status: status["status"],
        error_code: status.dig("errors", 0, "code"),
        error_title: status.dig("errors", 0, "title")
      }.compact
    end
  end
end
