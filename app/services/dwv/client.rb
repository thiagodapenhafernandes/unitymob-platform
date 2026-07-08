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
      response = RestClient::Request.execute(
        method: :get,
        url: "#{@base_url}#{path}",
        headers: {
          token: @token,
          accept: :json,
          params: params
        },
        timeout: 30,
        open_timeout: 10
      )

      JSON.parse(response.body)
    rescue JSON::ParserError
      raise RequestError, "Resposta DWV inválida (JSON malformado)."
    rescue RestClient::ExceptionWithResponse => e
      body = e.response&.body.to_s
      status = e.http_code
      raise RequestError, "Erro DWV (HTTP #{status}): #{body.presence || 'sem detalhes'}"
    rescue RestClient::Exception => e
      raise RequestError, "Erro de conexão DWV: #{e.message}"
    end
  end
end
