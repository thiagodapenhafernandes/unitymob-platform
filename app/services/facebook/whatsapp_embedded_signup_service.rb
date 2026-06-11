require "net/http"
require "uri"
require "json"

module Facebook
  class WhatsappEmbeddedSignupService
    class Error < StandardError; end

    DEFAULT_API_VERSION = "v24.0".freeze

    def initialize(code:, api_version: ENV["WHATSAPP_GRAPH_API_VERSION"].presence || ENV["META_API_VERSION"].presence || DEFAULT_API_VERSION)
      @code = code.to_s
      @api_version = api_version.to_s
    end

    def exchange_code!
      raise Error, "Código de autorização não recebido." if @code.blank?
      raise Error, "FACEBOOK_APP_ID não configurado." if app_id.blank?
      raise Error, "FACEBOOK_APP_SECRET não configurado." if app_secret.blank?

      response = perform_request
      parsed = JSON.parse(response.body)

      unless response.is_a?(Net::HTTPSuccess) && parsed["access_token"].present?
        message = parsed.dig("error", "message").presence || "Não foi possível trocar o código pelo token da Meta."
        raise Error, message
      end

      parsed
    rescue JSON::ParserError
      raise Error, "Resposta inválida da Meta ao trocar o código."
    end

    private

    def perform_request
      uri = URI.parse("https://graph.facebook.com/#{@api_version}/oauth/access_token")
      uri.query = URI.encode_www_form(request_params)
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 20, open_timeout: 10) do |http|
        http.get(uri.request_uri)
      end
    end

    def request_params
      {
        client_id: app_id,
        client_secret: app_secret,
        code: @code
      }
    end

    def app_id
      ENV["FACEBOOK_APP_ID"].to_s
    end

    def app_secret
      ENV["WHATSAPP_APP_SECRET"].presence || ENV["FACEBOOK_APP_SECRET"].to_s
    end
  end
end
