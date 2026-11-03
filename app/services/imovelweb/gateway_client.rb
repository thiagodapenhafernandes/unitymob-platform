module Imovelweb
  class GatewayClient
    def self.forwarding_secret
      ENV["IMOVELWEB_GATEWAY_FORWARDING_SECRET"]
    end

    def self.sync!(connection)
      base = Meta::WebhookGatewayClient.gateway_url
      host = ENV["APP_HOST"].to_s.delete_suffix("/")
      raise "Gateway Imovelweb não configurado." unless base.present? && Meta::WebhookGatewayClient.internal_token.present? && host.start_with?("https://") && forwarding_secret.to_s.length >= 32
      response = HTTParty.post("#{base}/internal/imovelweb/routes", timeout: 10,
        headers: { "Authorization" => "Bearer #{Meta::WebhookGatewayClient.internal_token}", "Content-Type" => "application/json" },
        body: { client_key: connection.route_key, client_code: connection.client_code, environment: connection.environment,
          target_url: "#{host}/webhooks/imovelweb/#{connection.route_key}", forwarding_secret: forwarding_secret,
          active: connection.receiving? }.to_json)
      raise "Não foi possível sincronizar a rota Imovelweb (HTTP #{response.code})." unless response.success?
      true
    end
  end
end
