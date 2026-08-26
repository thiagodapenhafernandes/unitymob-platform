module ExternalLeadMigration
  class IncrementalSyncJob < ApplicationJob
    queue_as :sync

    retry_on ExternalLeadMigration::Client::Error, Net::OpenTimeout, Net::ReadTimeout, Timeout::Error, wait: :polynomially_longer, attempts: 5

    PER_PAGE = 50

    def perform(integration_id, cursor_override = nil)
      integration = ExternalLeadIntegration.find(integration_id)
      return unless integration.connected?

      cursor = cursor_for(integration, cursor_override)
      client = ExternalLeadMigration::Client.new(token: integration.access_token)
      page = 1
      max_seen = nil

      loop do
        response = client.leads(
          page: page,
          perpage: PER_PAGE,
          params: { sort: "-updated_at", updated_gte: cursor }
        )
        rows = Array(response["data"])
        break if rows.empty?

        rows.each do |row|
          ExternalLeadMigration::LeadUpsert.call(integration:, payload: row, historical: false)
          updated_at = Time.zone.parse(row.dig("attributes", "updated_at").to_s) rescue nil
          max_seen = updated_at if updated_at && (max_seen.nil? || updated_at > max_seen)
        rescue => e
          integration.increment!(:failed_count)
          Rails.logger.warn("[ExternalLeadMigration Incremental] tenant_id=#{integration.tenant_id} erro=#{e.class}: #{e.message}")
        end

        total = response.dig("meta", "total").to_i
        break if page * PER_PAGE >= total

        page += 1
      end

      integration.update!(
        last_incremental_sync_at: Time.current,
        last_cursor_at: max_seen || Time.current,
        sync_status: "completed",
        sync_message: "Sincronização incremental externa concluída.",
        last_error_message: nil
      )
    rescue => e
      integration&.update(
        sync_status: "failed",
        sync_message: "Falha na sincronização incremental externa.",
        last_error_message: "#{e.class}: #{e.message}"
      )
      raise
    end

    private

    def cursor_for(integration, cursor_override)
      source =
        if cursor_override.present?
          Time.zone.parse(cursor_override.to_s)
        else
          integration.last_cursor_at || integration.last_backfill_at || 1.day.ago
        end

      source.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    end
  end
end
