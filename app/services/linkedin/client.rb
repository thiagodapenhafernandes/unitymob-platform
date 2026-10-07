require "net/http"

module Linkedin
  class Client
    class Error < StandardError; end
    SCOPES = "r_ads r_marketing_leadgen_automation".freeze

    def initialize(token = nil)
      @token = token
    end

    def authorization_url(state:)
      "https://www.linkedin.com/oauth/v2/authorization?#{URI.encode_www_form(response_type: 'code', client_id: ENV.fetch('LINKEDIN_CLIENT_ID'), redirect_uri: ENV.fetch('LINKEDIN_REDIRECT_URI'), scope: SCOPES, state: state)}"
    end

    def exchange_code(code)
      raise Error, "O LinkedIn não retornou uma autorização válida. Tente conectar novamente." if code.blank?

      uri = URI("https://www.linkedin.com/oauth/v2/accessToken")
      request = Net::HTTP::Post.new(uri)
      request.set_form_data(grant_type: "authorization_code", code: code, redirect_uri: ENV.fetch("LINKEDIN_REDIRECT_URI"), client_id: ENV.fetch("LINKEDIN_CLIENT_ID"), client_secret: ENV.fetch("LINKEDIN_CLIENT_SECRET"))
      send_request(uri, request)
    end

    def accounts
      search("adAccounts", q: "search", search: "(test:false)")
    end

    def campaigns(account_id)
      search("adAccounts/#{numeric_id(account_id)}/adCampaigns", q: "search", search: "(test:false)")
    end

    def creatives(account_id)
      search("adAccounts/#{numeric_id(account_id)}/creatives", q: "criteria", isTestAccount: "false")
    end

    def forms(account_id)
      collection("leadForms", q: "owner", owner: "(sponsoredAccount:urn:li:sponsoredAccount:#{numeric_id(account_id)})")
    end

    def form(form_id)
      get("leadForms/#{numeric_id(form_id)}")
    end

    def responses(account_id, from:, to:)
      collection("leadFormResponses", q: "owner", owner: "(sponsoredAccount:urn:li:sponsoredAccount:#{numeric_id(account_id)})", leadType: "(leadType:SPONSORED)", submittedAtTimeRange: "(start:#{from},end:#{to})", limitedToTestLeads: "false")
    end

    def self.id(value)
      value.to_s.split(":").last
    end

    private

    def numeric_id(value)
      id = self.class.id(value)
      raise Error, "Identificador inválido recebido do LinkedIn." unless id.match?(/\A\d+\z/)
      id
    end

    def search(path, **params)
      rows = []
      loop do
        data = get(path, params.merge(pageSize: 100))
        rows.concat(data.fetch("elements"))
        next_token = data.dig("metadata", "nextPageToken")
        break if next_token.blank?
        raise Error, "O LinkedIn repetiu a paginação. Tente novamente." if params[:pageToken] == next_token
        params[:pageToken] = next_token
      end
      rows
    end

    def collection(path, **params)
      rows = []
      start = 0
      loop do
        data = get(path, params.merge(start: start, count: 100))
        batch = data.fetch("elements")
        rows.concat(batch)
        start += batch.size
        total = data.dig("paging", "total")
        next_page = Array(data.dig("paging", "links")).any? { |link| link["rel"].to_s.downcase == "next" }
        break if batch.empty? || (total && start >= total.to_i) || (!total && !next_page && batch.size < 100)
      end
      rows
    end

    def get(path, params = {})
      uri = URI("https://api.linkedin.com/rest/#{path}")
      uri.query = URI.encode_www_form(params) if params.any?
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{@token}"
      request["LinkedIn-Version"] = ENV.fetch("LINKEDIN_API_VERSION", "202601")
      request["X-Restli-Protocol-Version"] = "2.0.0"
      send_request(uri, request)
    end

    def send_request(uri, request)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { |http| http.request(request) }
      unless response.is_a?(Net::HTTPSuccess)
        message = case response.code.to_i
        when 401 then "O acesso ao LinkedIn expirou. Reconecte sua conta."
        when 403 then "O LinkedIn recusou o acesso. Confira a aprovação Lead Sync e as permissões da conta de anúncios e da página."
        when 429 then "O LinkedIn atingiu o limite de consultas. O sistema tentará novamente."
        else "O LinkedIn não concluiu a consulta (HTTP #{response.code}). Tente novamente."
        end
        raise Error, message
      end
      JSON.parse(response.body)
    rescue JSON::ParserError, KeyError
      raise Error, "O LinkedIn retornou dados inválidos. Tente novamente."
    rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError
      raise Error, "Falha de comunicação com o LinkedIn. O sistema tentará novamente."
    end
  end
end
