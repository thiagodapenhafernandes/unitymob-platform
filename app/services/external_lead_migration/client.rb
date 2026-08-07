require "net/http"

module ExternalLeadMigration
  class Client
    BASE_URL = "https://api.contact2sale.com/integration".freeze
    DEFAULT_TIMEOUT = 20

    class Error < StandardError; end
    class UnauthorizedError < Error; end

    def initialize(token:, base_url: BASE_URL)
      @token = token.to_s.strip
      @base_url = base_url.to_s.chomp("/")
      raise ArgumentError, "Token da API externa obrigatório" if @token.blank?
    end

    def me
      get("/me")
    end

    def companies
      get("/companies")
    end

    def sellers
      get("/sellers")
    end

    def tags
      get("/tags")
    end

    def leads(page:, perpage: 50, params: {})
      get("/leads", params: {
        page: page,
        perpage: perpage,
        sort: "-created_at",
        first_message: true,
        custom_attributes: true,
        from_hierarchy_company: true
      }.merge(params))
    end

    def lead(id)
      get("/leads/#{id}")
    end

    def subscribe!(hook_action:, hook_url:)
      post("/api/subscribe", body: { hook_action: hook_action, hook_url: hook_url })
    end

    def unsubscribe!
      post("/api/unsubscribe", body: {})
    end

    private

    attr_reader :token, :base_url

    def get(path, params: {})
      request(Net::HTTP::Get, path, params: params)
    end

    def post(path, body:)
      request(Net::HTTP::Post, path, body: body)
    end

    def request(klass, path, params: {}, body: nil)
      uri = URI("#{base_url}#{path}")
      uri.query = URI.encode_www_form(params.compact) if params.present?

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = DEFAULT_TIMEOUT
      http.read_timeout = DEFAULT_TIMEOUT

      req = klass.new(uri)
      req["Accept"] = "application/json"
      req["Content-Type"] = "application/json"
      req["Authorization"] = "Bearer #{token}"
      req["Authentication"] = token
      req.body = body.to_json if body

      response = http.request(req)
      parsed = parse_body(response.body)

      case response.code.to_i
      when 200..299
        parsed
      when 401, 403
        raise UnauthorizedError, error_message(parsed, response)
      else
        raise Error, error_message(parsed, response)
      end
    end

    def parse_body(body)
      JSON.parse(body.to_s)
    rescue JSON::ParserError
      {}
    end

    def error_message(parsed, response)
      if parsed.is_a?(Hash)
        parsed["message"].presence || parsed["error"].presence || "HTTP #{response.code}"
      else
        "HTTP #{response.code}"
      end
    end
  end
end
