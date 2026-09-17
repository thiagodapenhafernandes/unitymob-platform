require "net/http"
require "uri"

module Lovers
  class Client
    API_BASE = "https://llapi.leadlovers.com/webapi".freeze

    def initialize(token:)
      @token = token.to_s.strip
    end

    def user
      get_json("/User")
    end

    def leads(page:, start_date: nil, end_date: nil)
      query = { page: page.to_i }
      query[:startDate] = format_date(start_date) if start_date.present?
      query[:endDate] = format_date(end_date) if end_date.present?
      get_json("/Leads", query)
    end

    def lead_sequence_history(page:, num_registers: 50)
      get_json("/EmailSequence/GetLeadsHistory", page: page.to_i, numRegisters: num_registers.to_i)
    end

    private

    attr_reader :token

    def get_json(path, query = {})
      uri = URI("#{API_BASE}#{path}")
      uri.query = URI.encode_www_form(query.merge(token:))

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 20, open_timeout: 10) do |http|
        request = Net::HTTP::Get.new(uri)
        request["Accept"] = "application/json"
        http.request(request)
      end

      raise_error!(path, response) unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body.presence || "{}")
    end

    def format_date(value)
      value.respond_to?(:strftime) ? value.strftime("%Y-%m-%d") : value.to_s
    end

    def raise_error!(path, response)
      detail = response&.body.to_s.presence || response&.message || "sem resposta"
      raise "Não foi possível consultar Lovers #{path}: HTTP #{response&.code} #{detail.truncate(300)}"
    end
  end
end
