module Portal
  class LeadGatewayClient
    def self.gateway_url
      Meta::WebhookGatewayClient.gateway_url
    end

    def self.public_gateway_url
      gateway_url.presence || "https://webhooks.unitymob.com.br"
    end

    def self.forwarding_secret
      ENV["GRUPOZAP_GATEWAY_FORWARDING_SECRET"].presence || Meta::WebhookGatewayClient.forwarding_secret
    end

    def self.configured?
      gateway_url.present? && Meta::WebhookGatewayClient.internal_token.present? &&
        forwarding_secret.to_s.length >= 20 && ENV["APP_HOST"].present?
    end

    def self.sync!(integration)
      raise "Gateway de leads não configurado pelo suporte." unless configured?

      response = HTTParty.post("#{gateway_url}/internal/grupozap/routes", timeout: 15,
        headers: { "Authorization" => "Bearer #{Meta::WebhookGatewayClient.internal_token}", "Content-Type" => "application/json" },
        body: {
          client_key: integration.lead_route_key, tenant_name: integration.tenant.name,
          target_url: "#{ENV.fetch('APP_HOST').delete_suffix('/')}/webhooks/portal_leads/grupozap/#{integration.lead_route_key}",
          forwarding_secret: forwarding_secret,
          active: integration.enabled? && integration.leads_enabled?
        }.to_json)
      raise "Gateway indisponível (HTTP #{response.code})." unless response.success?
      raise "Autenticação do Grupo OLX pendente no Gateway." unless JSON.parse(response.body).fetch("receiving_configured", false)
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, JSON::ParserError
      raise "Não foi possível atualizar a conexão com o Gateway."
    end
  end
end
