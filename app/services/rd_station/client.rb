require "net/http"
require "uri"

module RdStation
  class Client
    API_BASE = "https://api.rd.services".freeze
    AUTH_DIALOG_URL = "#{API_BASE}/auth/dialog".freeze
    TOKEN_URL = "#{API_BASE}/auth/token".freeze
    WEBHOOKS_URL = "#{API_BASE}/integrations/webhooks".freeze

    def initialize(setting:)
      @setting = setting
    end

    def authorization_url(redirect_uri:, state:)
      uri = URI(AUTH_DIALOG_URL)
      uri.query = URI.encode_www_form(
        client_id: setting.client_id,
        redirect_uri:,
        state:
      )
      uri.to_s
    end

    def exchange_code!(code:, redirect_uri:)
      response = post_json(TOKEN_URL, {
        client_id: setting.client_id,
        client_secret: setting.stored_client_secret,
        code: code.to_s,
        redirect_uri:
      })
      raise_error!("conectar", response) unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    def register_webhooks!(url:)
      events = %w[WEBHOOK.CONVERTED WEBHOOK.MARKED_OPPORTUNITY]
      responses = events.map { |event| register_webhook(event:, url:) }
      failed = responses.reject { |response| response.is_a?(Net::HTTPSuccess) || response.is_a?(Net::HTTPConflict) }
      raise_error!("registrar webhook", failed.first) if failed.any?

      responses
    end

    private

    attr_reader :setting

    def register_webhook(event:, url:)
      authenticated_post_json(WEBHOOKS_URL, { event_type: event, url:, http_method: "POST" })
    end

    def authenticated_post_json(url, payload)
      response = post_json(url, payload, authorization: "Bearer #{access_token!}")
      return response unless response.is_a?(Net::HTTPUnauthorized) && setting.refresh_token.present?

      refresh_access_token!
      post_json(url, payload, authorization: "Bearer #{setting.access_token}")
    end

    def access_token!
      refresh_access_token! if setting.access_token_expired? && setting.refresh_token.present?
      setting.access_token
    end

    def refresh_access_token!
      response = post_json(TOKEN_URL, {
        client_id: setting.client_id,
        client_secret: setting.stored_client_secret,
        refresh_token: setting.refresh_token
      })
      raise_error!("renovar token", response) unless response.is_a?(Net::HTTPSuccess)

      RdStationIntegrationSetting.save_oauth_tokens!(tenant: setting.tenant, payload: JSON.parse(response.body))
      setting.access_token
    end

    def post_json(url, payload, authorization: nil)
      uri = URI(url)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = authorization if authorization.present?
      request.body = payload.to_json

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", read_timeout: 20, open_timeout: 10) do |http|
        http.request(request)
      end
    end

    def raise_error!(action, response)
      body = response&.body.to_s
      detail = body.presence || response&.message || "sem resposta"
      raise "Não foi possível #{action} na RD Station: HTTP #{response&.code} #{detail.truncate(300)}"
    end
  end
end
