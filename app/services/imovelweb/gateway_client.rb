module Imovelweb
  class GatewayClient
    def self.forwarding_secret
      ENV["IMOVELWEB_GATEWAY_FORWARDING_SECRET"]
    end

    class Error < RuntimeError; end

    def self.verify!(connection)
      data = request!("verification", connection, extra: { binding_proof: connection.binding_proof })
      unless [true, false].include?(data["confirmed"]) && [nil, true, false].include?(data["ownership_required"]) &&
          (!(data["confirmed"] || data["ownership_required"]) || data["advertiser_code"].to_s.match?(/\A[0-9]+\z/))
        raise Error, "Não foi possível confirmar a autorização no Imovelweb."
      end
      data
    end

    def self.start_confirmation!(connection)
      data = request!("challenge", connection)
      unless data["challenge_token"].to_s.match?(/\A[A-Za-z0-9_-]{40,80}\z/) && data["email_hint"].is_a?(String)
        raise Error, "Não foi possível enviar o código de confirmação."
      end
      data
    end

    def self.confirm!(connection, code:)
      data = request!("confirmation", connection, extra: { challenge_token: connection.binding_challenge_token, code: code })
      proof = data["binding_proof"]
      raise Error, "Código inválido ou expirado. Solicite um novo código." unless proof.to_s.match?(/\A[0-9a-f]{64}\z/)
      proof
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
        body: { client_code: connection.client_code, environment: connection.environment, client_key: connection.route_key }.merge(extra).to_json)
      unless response.success?
        message = case response.code.to_i
        when 409 then "A sucursal já está vinculada a outra conta ou aguarda confirmação de titularidade."
        when 429 then "Aguarde alguns minutos antes de solicitar outro código."
        when 422 then "Não foi possível confirmar. Verifique o código recebido e a autorização no Imovelweb."
        else "Conexão com o Imovelweb indisponível. Tente novamente em instantes."
        end
        raise Error, message
      end
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
          active: connection.receiving?, binding_proof: connection.binding_proof, advertiser_code: (connection.advertiser_code if connection.authorized_at.present?) }.compact.to_json)
      raise Error, "Não foi possível sincronizar a rota Imovelweb (HTTP #{response.code})." unless response.success?
      true
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, Errno::ECONNREFUSED, OpenSSL::SSL::SSLError
      raise Error, "Não foi possível atualizar a conexão. Tentaremos novamente."
    end
  end
end
