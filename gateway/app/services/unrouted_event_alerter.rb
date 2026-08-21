# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Gateway
  module UnroutedEventAlerter
    TIMEOUT_SECONDS = 3

    module_function

    def call(event)
      warn(log_line(event))
      return if webhook_url.empty?

      post_alert(event)
    rescue StandardError => error
      warn("[gateway unrouted alert failed] event_id=#{event&.id} error=#{error.class}: #{error.message}")
    end

    def log_line(event)
      [
        "[gateway unrouted]",
        "event_id=#{event.id}",
        "provider=#{event.provider}",
        "event_type=#{event.event_type}",
        "external_id=#{event.external_id}",
        "waba_id=#{event.waba_id}",
        "phone_number_id=#{event.phone_number_id}",
        "page_id=#{event.page_id}",
        "form_id=#{event.form_id}"
      ].join(" ")
    end

    def post_alert(event)
      uri = URI(webhook_url)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = alert_payload(event).to_json

      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
        http.request(request)
      end
    end

    def alert_payload(event)
      {
        alert: "gateway_unrouted_webhook_event",
        event_id: event.id,
        provider: event.provider,
        event_type: event.event_type,
        external_id: event.external_id,
        waba_id: event.waba_id,
        phone_number_id: event.phone_number_id,
        page_id: event.page_id,
        form_id: event.form_id,
        received_at: event.received_at&.iso8601
      }
    end

    def webhook_url
      ENV["GATEWAY_UNROUTED_ALERT_WEBHOOK_URL"].to_s.strip
    end
  end
end
