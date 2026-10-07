module Tiktok
  class GatewayClient
    def self.forwarding_secret
      ENV["TIKTOK_GATEWAY_FORWARDING_SECRET"].presence || Meta::WebhookGatewayClient.forwarding_secret
    end

    def self.configured?
      Meta::WebhookGatewayClient.gateway_url.start_with?("https://") && Meta::WebhookGatewayClient.internal_token.present? &&
        forwarding_secret.to_s.length >= 20 && ENV["APP_HOST"].to_s.start_with?("https://") &&
        ENV["TIKTOK_REDIRECT_URI"] == "#{Meta::WebhookGatewayClient.gateway_url}/oauth/tiktok/callback" && ENV["TIKTOK_WEBHOOK_TOKEN"].to_s.match?(/\A[0-9a-f]{64}\z/)
    end

    def self.callback_url(integration)
      "#{Meta::WebhookGatewayClient.gateway_url}/webhooks/tiktok?#{URI.encode_www_form(webhook_token: ENV.fetch('TIKTOK_WEBHOOK_TOKEN'), connection_key: integration.route_key)}"
    end

    def self.owns_callback?(url, integration)
      uri = URI.parse(url.to_s)
      gateway = URI.parse(Meta::WebhookGatewayClient.gateway_url)
      uri.scheme == gateway.scheme && uri.host == gateway.host && uri.port == gateway.port && uri.path == "/webhooks/tiktok" &&
        URI.decode_www_form(uri.query.to_s).to_h["connection_key"] == integration.route_key
    rescue URI::InvalidURIError, ArgumentError
      false
    end

    def self.register_oauth!(state:, return_url:)
      response = HTTParty.post("#{Meta::WebhookGatewayClient.gateway_url}/internal/tiktok/oauth_states", timeout: 15,
        headers: { "Authorization" => "Bearer #{Meta::WebhookGatewayClient.internal_token}", "Content-Type" => "application/json" },
        body: { state: state, return_url: return_url }.to_json)
      raise Client::Error, "Não foi possível iniciar a conexão com o TikTok." unless response.success?
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED
      raise Client::Error, "Não foi possível iniciar a conexão com o TikTok. Tente novamente."
    end

    def self.pause_unselected!(integration)
      response = HTTParty.post("#{Meta::WebhookGatewayClient.gateway_url}/internal/tiktok/connections/#{integration.route_key}", timeout: 15,
        headers: { "Authorization" => "Bearer #{Meta::WebhookGatewayClient.internal_token}", "Content-Type" => "application/json" },
        body: { advertiser_ids: integration.selected_account_ids }.to_json)
      raise Client::Error, "Não foi possível interromper as rotas TikTok desmarcadas." unless response.success?
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED
      raise Client::Error, "Não foi possível atualizar o Gateway TikTok. O sistema tentará novamente."
    end

    def self.sync!(integration, advertiser_id, active:)
      raise Client::Error, "O Gateway TikTok precisa ser habilitado pelo suporte." unless configured?
      response = HTTParty.post("#{Meta::WebhookGatewayClient.gateway_url}/internal/tiktok/routes", timeout: 15,
        headers: { "Authorization" => "Bearer #{Meta::WebhookGatewayClient.internal_token}", "Content-Type" => "application/json" },
        body: { client_key: integration.route_key, advertiser_id: advertiser_id, tenant_name: integration.tenant.name,
          target_url: "#{ENV.fetch('APP_HOST').delete_suffix('/')}/webhooks/tiktok/#{integration.route_key}",
          forwarding_secret: forwarding_secret, active: active }.to_json)
      raise Client::Error, "Este anunciante já está vinculado a outra conta Unitymob. Contate o suporte." if response.code == 409
      raise Client::Error, "Não foi possível atualizar o Gateway TikTok (HTTP #{response.code})." unless response.success?
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED
      raise Client::Error, "Não foi possível atualizar o Gateway TikTok. O sistema tentará novamente."
    end
  end
end
