require "googleauth"
require "net/http"
require "stringio"

module Ga4
  class ReportingClient
    EVENTS = %w[generate_lead qualify_lead visit_completed proposal_sent close_convert_lead].freeze

    def self.call(config:, start_date:, end_date:)
      raise ArgumentError, "Invalid property" unless config.reporting_property_id.to_s.match?(/\A[1-9]\d{0,19}\z/)

      credentials = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(config.reporting_credentials_data.to_json),
        scope: "https://www.googleapis.com/auth/analytics.readonly"
      )
      token = credentials.fetch_access_token!(connection: Faraday.new(request: { timeout: 5, open_timeout: 3 })).fetch("access_token")
      uri = URI("https://analyticsdata.googleapis.com/v1beta/properties/#{config.reporting_property_id}:runReport")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{token}"
      request["Content-Type"] = "application/json"
      request.body = {
        dateRanges: [{ startDate: start_date.iso8601, endDate: end_date.iso8601 }],
        dimensions: [{ name: "eventName" }], metrics: [{ name: "eventCount" }],
        dimensionFilter: { filter: { fieldName: "eventName", inListFilter: { values: EVENTS } } }, limit: 20
      }.to_json
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 3
      http.read_timeout = http.write_timeout = 5
      http.max_retries = 0
      response = http.start { |connection| connection.request(request) }
      raise IOError, "GA4 reporting unavailable" unless response.code.to_i == 200

      data = JSON.parse(response.body)
      valid_headers = data.is_a?(Hash) && data.fetch("dimensionHeaders", []).map { |header| header["name"] } == ["eventName"] &&
        data.fetch("metricHeaders", []).map { |header| header["name"] } == ["eventCount"]
      raise TypeError, "Invalid GA4 report" unless valid_headers

      counts = EVENTS.index_with { 0 }
      data.fetch("rows", []).each do |row|
        name = row.fetch("dimensionValues").first.fetch("value")
        value = row.fetch("metricValues").first.fetch("value")
        raise TypeError unless value.match?(/\A\d+\z/)

        counts[name] = Integer(value, 10) if EVENTS.include?(name)
      end
      metadata = data.fetch("metadata", {})
      {
        status: :ok, counts: counts, queried_at: Time.current,
        timezone: metadata["timeZone"],
        limited: metadata["subjectToThresholding"] == true || metadata["dataLossFromOtherRow"] == true || metadata["samplingMetadatas"].present?
      }
    end
  end
end
