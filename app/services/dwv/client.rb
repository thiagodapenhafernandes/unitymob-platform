module Dwv
  class Client
    class RequestError < StandardError; end

    def initialize(token:, base_url:)
      @token = token.to_s.strip
      @base_url = base_url.to_s.strip.chomp("/")
    end

    def list_properties(limit: 20, page: 1, deleted: nil, last_updates: nil, status: nil)
      params = { limit: limit, page: page }
      params[:deleted] = deleted unless deleted.nil?
      params[:last_updates] = last_updates if last_updates.present?
      params[:status] = status if status.present?
      get("/integration/properties", params: params)
    end

    def property_details(property_id)
      get("/integration/properties/#{property_id}")
    end

    private

    def get(path, params: {})
      response = HTTParty.get(
        "#{@base_url}#{path}",
        query: params,
        headers: { "token" => @token, "Accept" => "application/json" },
        timeout: 30,
        open_timeout: 10
      )
      unless response.code.to_i.between?(200, 299)
        raise RequestError, "Erro DWV (HTTP #{response.code}): #{response.body.presence || 'sem detalhes'}"
      end

      JSON.parse(response.body)
    rescue JSON::ParserError
      raise RequestError, "Resposta DWV inválida (JSON malformado)."
    rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
      raise RequestError, "Erro de conexão DWV: #{e.message}"
    end
  end
end
