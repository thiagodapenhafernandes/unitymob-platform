module Meta
  class WebhookGatewayClient
    Result = Struct.new(:ok?, :skipped?, :status, :error, :data, keyword_init: true)

    def self.enabled?
      WebhookConfiguration.gateway? && gateway_url.present? && internal_token.present? && forwarding_secret.present? && target_url.present?
    end

    def self.gateway_url
      ENV["WHATSAPP_WEBHOOK_GATEWAY_URL"].to_s.delete_suffix("/")
    end

    def self.public_webhook_url
      ENV["META_LEADS_WEBHOOK_GATEWAY_PUBLIC_URL"].presence || gateway_url.presence&.then { |url| "#{url}/webhooks/meta" }
    end

    def self.internal_token
      ENV["WHATSAPP_WEBHOOK_GATEWAY_INTERNAL_TOKEN"].presence
    end

    def self.forwarding_secret
      ENV["WHATSAPP_WEBHOOK_GATEWAY_FORWARDING_SECRET"].presence
    end

    def self.verify_token
      ENV["WHATSAPP_WEBHOOK_GATEWAY_VERIFY_TOKEN"].presence || Setting.get("facebook_webhook_verify_token", ENV["FACEBOOK_WEBHOOK_VERIFY_TOKEN"])
    end

    def self.target_url
      ENV["META_LEADS_WEBHOOK_TARGET_URL"].presence ||
        ENV["APP_HOST"].presence&.delete_suffix("/")&.then { |host| "#{host}/webhooks/meta" }
    end

    def initialize(page:, tenant:, form: nil, target_url: self.class.target_url)
      @page = page
      @tenant = tenant
      @form = form
      @target_url = target_url
    end

    def register_route
      return skipped("Webhook Meta configurado em modo app próprio; gateway não será registrado.") unless WebhookConfiguration.gateway?
      return skipped("Gateway de webhooks Meta não configurado.") unless self.class.enabled?
      return skipped("Página Meta ainda não possui Page ID.") unless page.page_id.present?
      return skipped("Endpoint de destino Meta não configurado.") unless target_url.present?

      response = HTTParty.post(
        "#{self.class.gateway_url}/internal/meta/routes",
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

    attr_reader :page, :tenant, :form, :target_url

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
        page_id: page.page_id,
        form_id: form&.form_id,
        target_url: target_url,
        forwarding_secret: self.class.forwarding_secret,
        active: form ? page.active? && form.active? : page.active?
      }
    end

    def parse(response)
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      {}
    end

    def gateway_error(response, parsed)
      parsed["error"].presence || Array(parsed["details"]).presence&.join(", ") || "Erro #{response.code} ao registrar rota Meta no gateway."
    end

    def skipped(message)
      Result.new(ok?: false, skipped?: true, status: nil, data: {}, error: message)
    end
  end
end
