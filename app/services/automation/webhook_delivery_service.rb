module Automation
  class WebhookDeliveryService
    class TransientError < StandardError; end

    TIMEOUT = 10

    def self.call(delivery)
      new(delivery).call
    end

    def initialize(delivery)
      @delivery = delivery
    end

    def call
      delivery.update!(status: "pending", attempts: delivery.attempts.to_i + 1, sent_at: Time.current)

      response = HTTParty.public_send(
        delivery.http_method,
        delivery.url,
        headers: default_headers.merge(delivery.request_headers.to_h),
        body: delivery.request_payload.to_json,
        timeout: TIMEOUT
      )

      delivery.update!(
        status: response.success? ? "success" : "failed",
        response_code: response.code,
        response_body: response.body.to_s.truncate(4000),
        responded_at: Time.current,
        error_message: response.success? ? nil : "HTTP #{response.code}"
      )

      raise TransientError, "HTTP #{response.code}" if retriable?(response)
    rescue => e
      delivery.update!(
        status: "failed",
        error_message: e.message.to_s.truncate(500),
        responded_at: Time.current
      )
      raise
    end

    private

    attr_reader :delivery

    def default_headers
      {
        "Content-Type" => "application/json",
        "User-Agent" => "Unitymob-CRM-Automation/1.0"
      }
    end

    def retriable?(response)
      response.code.to_i == 408 || response.code.to_i == 429 || response.code.to_i >= 500
    end
  end
end
