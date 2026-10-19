module Ga4
  class ReportSnapshot
    def self.call(config:, start_date:, end_date:)
      return { status: :not_configured } unless config&.reporting_configured?

      key = ["ga4-report-v1", config.tenant_id, config.cache_key_with_version, start_date.iso8601, end_date.iso8601]
      Rails.cache.fetch(key, expires_in: 15.minutes, race_condition_ttl: 10.seconds) do
        begin
          result = ReportingClient.call(config: config, start_date: start_date, end_date: end_date)
          Rails.cache.write([*key, "last-good"], result, expires_in: 1.day)
          result
        rescue StandardError => error
          Rails.logger.warn("[GA4_REPORT] tenant_id=#{config.tenant_id} error_class=#{error.class.name}")
          previous = Rails.cache.read([*key, "last-good"])
          previous ? previous.merge(status: :stale) : { status: :unavailable }
        end
      end
    end
  end
end
