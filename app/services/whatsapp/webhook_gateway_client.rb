module Whatsapp
  class WebhookGatewayClient
    Result = Struct.new(:ok?, :skipped?, :status, :error, :data, keyword_init: true)

    def self.enabled?
      gateway_url.present? && internal_token.present? && forwarding_secret.present?
    end

    def self.gateway_url
      ENV["WHATSAPP_WEBHOOK_GATEWAY_URL"].to_s.delete_suffix("/")
    end

    def self.public_webhook_url
      ENV["WHATSAPP_WEBHOOK_GATEWAY_PUBLIC_URL"].presence || gateway_url.presence&.then { |url| "#{url}/webhooks/whatsapp" }
    end

    def self.internal_token
      ENV["WHATSAPP_WEBHOOK_GATEWAY_INTERNAL_TOKEN"].presence
    end

    def self.forwarding_secret
      ENV["WHATSAPP_WEBHOOK_GATEWAY_FORWARDING_SECRET"].presence
    end

    def self.verify_token
      ENV["WHATSAPP_WEBHOOK_GATEWAY_VERIFY_TOKEN"].presence
    end

    def initialize(integration:, tenant:, target_url:)
      @integration = integration
      @tenant = tenant
      @target_url = target_url
    end

    def register_route
      return skipped("Gateway de webhooks não configurado.") unless self.class.enabled?
      return skipped("Integração WhatsApp ainda não possui WABA e Phone Number ID.") unless integration.waba_id.present? && integration.phone_number_id.present?

      response = HTTParty.post(
        "#{self.class.gateway_url}/internal/whatsapp/routes",
        headers: headers,
        body: route_payload.to_json,
        timeout: 15
      )
      parsed = parse(response)
      return Result.new(ok?: true, skipped?: false, status: response.code, data: parsed) if response.success?

      Result.new(ok?: false, skipped?: false, status: response.code, data: parsed, error: gateway_error(response, parsed))
    rescue => e
      Result.new(ok?: false, skipped?: false, status: 0, data: {}, error: e.message)
    end

    private

    attr_reader :integration, :tenant, :target_url

    def headers
      {
        "Authorization" => "Bearer #{self.class.internal_token}",
        "Content-Type" => "application/json"
      }
    end

    def route_payload
      {
        client_key: tenant.slug.presence || "tenant-#{tenant.id}",
        tenant_name: tenant.name,
        waba_id: integration.waba_id,
        phone_number_id: integration.phone_number_id,
        target_url: target_url,
        forwarding_secret: self.class.forwarding_secret,
        active: true
      }
    end

    def parse(response)
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      {}
    end

    def gateway_error(response, parsed)
      parsed["error"].presence || Array(parsed["details"]).presence&.join(", ") || "Erro #{response.code} ao registrar rota no gateway."
    end

    def skipped(message)
      Result.new(ok?: false, skipped?: true, status: nil, data: {}, error: message)
    end
  end
end
