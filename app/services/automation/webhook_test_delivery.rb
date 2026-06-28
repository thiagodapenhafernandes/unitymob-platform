module Automation
  class WebhookTestDelivery
    def self.call(url:, http_method:, headers:, payload_template: nil)
      new(url, http_method, headers, payload_template).call
    end

    def initialize(url, http_method, headers, payload_template = nil)
      @url = url.to_s.strip
      @http_method = http_method.presence || "post"
      @headers = headers
      @payload_template = payload_template.to_s
    end

    def call
      delivery = AutomationWebhookDelivery.create!(
        url: url,
        http_method: http_method,
        request_headers: parse_headers(headers),
        request_payload: payload
      )

      Automation::WebhookDeliveryService.call(delivery)
      delivery
    rescue Automation::WebhookDeliveryService::TransientError
      delivery
    end

    private

    attr_reader :url, :http_method, :headers, :payload_template

    def payload
      parsed_payload = parse_payload_template
      return parsed_payload if parsed_payload.present?

      {
        event: "webhook_test",
        source: "automation",
        occurred_at: Time.current.iso8601,
        message: "Teste de webhook da Automação do UnityMob CRM"
      }
    end

    def parse_payload_template
      return nil if payload_template.blank?

      parsed = JSON.parse(payload_template)
      parsed if parsed.is_a?(Hash)
    rescue JSON::ParserError
      { raw: payload_template }
    end

    def parse_headers(value)
      return value.to_h if value.is_a?(Hash)

      value.to_s.lines.each_with_object({}) do |line, memo|
        key, header_value = line.split(":", 2).map { |part| part.to_s.strip }
        memo[key] = header_value if key.present? && header_value.present?
      end
    end
  end
end
