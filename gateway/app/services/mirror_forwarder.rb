# frozen_string_literal: true

require "net/http"
require "uri"

module Gateway
  class MirrorForwarder
    TIMEOUT_SECONDS = 3

    def self.call(event:, raw_body:)
      return unless ENV.fetch("GATEWAY_DEV_MIRROR_ENABLED", "true") == "true"

      WebhookMirror.active_for(event.provider).find_each do |mirror|
        new(mirror:, event:, raw_body:).call
      end
    end

    def initialize(mirror:, event:, raw_body:)
      @mirror = mirror
      @event = event
      @raw_body = raw_body
    end

    def call
      mirror.update!(last_attempted_at: Time.now, last_status: "attempting", last_error: nil)
      response = perform_request
      if response.is_a?(Net::HTTPSuccess)
        mirror.update!(last_status: "forwarded", last_succeeded_at: Time.now, last_error: nil)
      else
        mirror.update!(last_status: "failed", last_error: "HTTP #{response.code}: #{response.body.to_s[0, 500]}")
      end
      response
    rescue StandardError => error
      mirror.update!(last_status: "failed", last_error: "#{error.class}: #{error.message}")
      nil
    end

    private

    attr_reader :mirror, :event, :raw_body

    def perform_request
      uri = target_uri
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["X-Unitymob-Gateway-Signature"] = InternalSignature.sign(raw_body, secret: mirror.forwarding_secret)
      request["X-Unitymob-Gateway-Event-Id"] = event.id.to_s
      request["X-Unitymob-Gateway-Provider"] = event.provider
      request["X-Unitymob-Gateway-Mirror"] = "dev"
      request.body = raw_body

      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: TIMEOUT_SECONDS, read_timeout: TIMEOUT_SECONDS) do |http|
        http.request(request)
      end
    end

    def target_uri
      URI(mirror.target_url).tap do |uri|
        next unless mirror.provider == "all" || uri.path.to_s.empty? || uri.path == "/"

        uri.path = "/webhooks/#{event.provider}"
        uri.query = nil
        uri.fragment = nil
      end
    end
  end
end
