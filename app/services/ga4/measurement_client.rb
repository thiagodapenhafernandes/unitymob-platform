require "net/http"

module Ga4
  class MeasurementClient
    Result = Data.define(:outcome, :http_status)

    def self.deliver(config:, payload:)
      uri = URI("https://www.google-analytics.com/mp/collect")
      uri.query = URI.encode_www_form(measurement_id: config.measurement_id, api_secret: config.api_secret)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(payload)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 3
      http.read_timeout = 5
      http.write_timeout = 5
      http.max_retries = 0
      response = http.start { |connection| connection.request(request) }
      code = response.code.to_i
      Result.new(outcome: code.between?(200, 299) ? "http_accepted" : "rejected", http_status: code)
    rescue StandardError
      # Sem resposta conclusiva, reenviar pode duplicar: exige conciliação humana.
      Result.new(outcome: "uncertain", http_status: nil)
    end
  end
end
