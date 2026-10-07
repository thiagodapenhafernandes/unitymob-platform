require "net/http"

module Tiktok
  class Client
    class Error < StandardError; end
    BASE_URL = "https://business-api.tiktok.com/open_api/v1.3/".freeze

    def initialize(token = nil)
      @token = token
    end

    def authorization_url(state:)
      "https://business-api.tiktok.com/portal/auth?#{URI.encode_www_form(app_id: ENV.fetch('TIKTOK_APP_ID'), redirect_uri: ENV.fetch('TIKTOK_REDIRECT_URI'), state: state)}"
    end

    def exchange_code(code)
      raise Error, "O TikTok não retornou uma autorização válida. Conecte novamente." if code.blank?
      request("oauth2/access_token/", credentials.merge(auth_code: code), post: true)
    end

    def accounts
      request("oauth2/advertiser/get/", credentials).fetch("list")
    end

    def forms(advertiser_id)
      collection("page/get/", "list", advertiser_id: advertiser_id, business_type: "LEAD_GEN", status: "PUBLISHED")
    end

    def subscriptions
      collection("subscription/get/", "subscriptions", **credentials, subscribe_entity: "LEAD")
    end

    def subscribe(advertiser_id, integration:)
      data = request("subscription/subscribe/", credentials.merge(subscribe_entity: "LEAD", callback_url: GatewayClient.callback_url(integration),
        subscription_detail: { access_token: @token, advertiser_id: advertiser_id, lead_source: "INSTANT_FORM" }), post: true)
      data.fetch("subscription_id").to_s.presence || raise(Error, "O TikTok não confirmou a inscrição para receber leads.")
    end

    def unsubscribe(subscription_id)
      request("subscription/unsubscribe/", credentials.merge(subscription_id: subscription_id), post: true)
    end

    private

    def credentials
      { app_id: ENV.fetch("TIKTOK_APP_ID"), secret: ENV.fetch("TIKTOK_APP_SECRET") }
    end

    def collection(path, key, **params)
      rows = []
      page = 1
      loop do
        data = request(path, params.merge(page: page, page_size: 100))
        batch = data.fetch(key)
        raise Error, "O TikTok retornou uma lista inválida." unless batch.is_a?(Array)
        rows.concat(batch)
        break if page >= data.fetch("page_info").fetch("total_page").to_i
        page += 1
      end
      rows
    end

    def request(path, data, post: false)
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(data) unless post
      req = post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
      req["Access-Token"] = @token if @token
      if post
        req["Content-Type"] = "application/json"
        req.body = data.to_json
      end
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { |http| http.request(req) }
      raise Error, "O TikTok não concluiu a operação (HTTP #{response.code}). Tente novamente." unless response.is_a?(Net::HTTPSuccess)
      result = JSON.parse(response.body)
      unless result.is_a?(Hash) && result["code"] == 0 && result["data"].is_a?(Hash)
        raise Error, "O TikTok recusou a operação. Confira as permissões do aplicativo e o acesso de administrador ao anunciante."
      end
      result.fetch("data")
    rescue JSON::ParserError, KeyError, TypeError
      raise Error, "O TikTok retornou dados inválidos. Tente novamente."
    rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError
      raise Error, "Falha de comunicação com o TikTok. O sistema tentará novamente."
    end
  end
end
