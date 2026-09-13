# frozen_string_literal: true

require "net/http"
require "uri"

module Gateway
  class EventForwarder
    TIMEOUT_SECONDS = 5
    MAX_BACKOFF_SECONDS = 15 * 60

    def self.call(event:, raw_body:)
      new(event:, raw_body:).call
    end

    def initialize(event:, raw_body:)
      @event = event
      @raw_body = raw_body
      @route = event.webhook_route
    end

    def call
      event.increment!(:attempts)
      event.update!(last_attempted_at: Time.now)

      response = perform_request
      if response.is_a?(Net::HTTPSuccess)
        event.update!(status: "forwarded", forwarded_at: Time.now, last_error: nil, next_retry_at: nil)
      else
        mark_failed!("HTTP #{response.code}: #{response.body.to_s[0, 500]}")
      end

      response
    rescue StandardError => error
      mark_failed!("#{error.class}: #{error.message}")
      nil
    end

    private

    attr_reader :event, :raw_body, :route

    def perform_request
      if event.provider == "meta"
        contexts = MetaLeadPayload.extract_event_contexts(JSON.parse(raw_body))
        matching = contexts.select { |context| context[:page_id].to_s == event.page_id.to_s && context[:external_id].to_s == event.external_id.to_s && context[:form_id].to_s == event.form_id.to_s }
        raise "Meta event cannot be isolated" unless matching.one? && matching.first[:payload]
        raise "Meta route does not match event" unless route.active? && route.page_id.to_s == event.page_id.to_s
        @raw_body = JSON.generate(matching.first[:payload])
      end
      uri = URI(route.target_url)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["X-Unitymob-Gateway-Signature"] = InternalSignature.sign(raw_body, secret: route.forwarding_secret)
      request["X-Unitymob-Gateway-Event-Id"] = event.id.to_s
      request["X-Unitymob-Gateway-Provider"] = event.provider
      request.body = raw_body

      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
        http.request(request)
      end
    end

    def mark_failed!(message)
      event.update!(
        status: "failed",
        last_error: message,
        next_retry_at: Time.now + backoff_seconds
      )
    end

    def backoff_seconds
      [2**event.attempts, MAX_BACKOFF_SECONDS].min
    end
  end
end
