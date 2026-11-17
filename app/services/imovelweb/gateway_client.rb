module Imovelweb
  class GatewayClient
    def self.forwarding_secret
      ENV["IMOVELWEB_GATEWAY_FORWARDING_SECRET"]
    end

    class Error < RuntimeError; end

    def self.authorization_script(connection)
      data = request!("authorization", connection)
      url = data["script_url"].to_s
      unless url.match?(%r{\Ahttps://loginbr-open\.navent\.com/[A-Za-z0-9_-]+/#{Regexp.escape(connection.client_code)}\.js\z})
        raise Error, "Autorização do Imovelweb indisponível."
      end
      url
    end

    def self.verify!(connection)
      data = request!("verification", connection)
      unless [true, false].include?(data["confirmed"]) && (!data["confirmed"] || data["advertiser_code"].to_s.match?(/\A[0-9]+\z/))
        raise Error, "Não foi possível confirmar a autorização no Imovelweb."
      end
      data["confirmed"] ? data.fetch("advertiser_code").to_s : nil
    end

    def self.associate_listings!(connection, page:)
      data = request!("listings", connection, extra: { client_key: connection.route_key, page: page }, timeout: 60)
      following = data["next_page"]
      unless following.nil? || (following.is_a?(Integer) && following == page + 1 && following <= 999)
        raise Error, "Não foi possível concluir a preparação dos anúncios."
      end
      following
    end

    def self.request!(action, connection, extra: {}, timeout: 15)
      base = Meta::WebhookGatewayClient.gateway_url
      token = Meta::WebhookGatewayClient.internal_token
      raise Error, "Conexão com o Imovelweb indisponível." unless base.present? && token.present?
      response = HTTParty.post("#{base}/internal/imovelweb/#{action}", timeout: timeout,
        headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" },
        body: { client_code: connection.client_code, environment: connection.environment }.merge(extra).to_json)
      raise Error, "Conexão com o Imovelweb indisponível. Tente novamente em instantes." unless response.success?
      data = JSON.parse(response.body)
      raise Error, "Resposta inválida do Imovelweb." unless data.is_a?(Hash)
      data
    rescue JSON::ParserError, Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError
      raise Error, "Conexão com o Imovelweb indisponível. Tente novamente em instantes."
    end
    private_class_method :request!

    def self.sync!(connection)
      base = Meta::WebhookGatewayClient.gateway_url
      host = ENV["APP_HOST"].to_s.delete_suffix("/")
      raise Error, "Gateway Imovelweb não configurado." unless base.present? && Meta::WebhookGatewayClient.internal_token.present? && host.start_with?("https://") && forwarding_secret.to_s.length >= 32
      response = HTTParty.post("#{base}/internal/imovelweb/routes", timeout: 10,
        headers: { "Authorization" => "Bearer #{Meta::WebhookGatewayClient.internal_token}", "Content-Type" => "application/json" },
        body: { client_key: connection.route_key, client_code: connection.client_code, environment: connection.environment,
          target_url: "#{host}/webhooks/imovelweb/#{connection.route_key}", forwarding_secret: forwarding_secret,
          active: connection.receiving?, advertiser_code: (connection.advertiser_code if connection.authorized_at.present?) }.compact.to_json)
      raise Error, "Não foi possível sincronizar a rota Imovelweb (HTTP #{response.code})." unless response.success?
      true
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError
      raise Error, "Não foi possível atualizar a conexão. Tentaremos novamente."
    end
  end
end
