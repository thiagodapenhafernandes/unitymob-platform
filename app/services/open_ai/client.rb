require "json"
require "net/http"
require "uri"

module OpenAi
  class Client
    API_URL = "https://api.openai.com/v1/responses".freeze

    def initialize(api_key:)
      @api_key = api_key.to_s.strip
    end

    def create_response(payload)
      raise "Token da OpenAI não configurado." if @api_key.blank?

      uri = URI.parse(API_URL)
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"
      request.body = payload.to_json

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 90, open_timeout: 15) do |http|
        http.request(request)
      end

      parsed = JSON.parse(response.body) rescue {}
      unless response.is_a?(Net::HTTPSuccess)
        message = parsed.dig("error", "message").presence || response.message
        raise "OpenAI retornou erro #{response.code}: #{message}"
      end

      parsed
    end
  end
end
