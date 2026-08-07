module ExternalLeadMigration
  class BackfillLeadsJob < ApplicationJob
    queue_as :sync

    retry_on ExternalLeadMigration::Client::Error, wait: :polynomially_longer, attempts: 5

    PER_PAGE = 50

    def perform(integration_id, page = 1)
      integration = ExternalLeadIntegration.find(integration_id)
      return unless integration.connected?

      client = ExternalLeadMigration::Client.new(token: integration.access_token)
      response = client.leads(page: page, perpage: PER_PAGE)
      rows = Array(response["data"])
      total = response.dig("meta", "total").to_i

      integration.update!(
        sync_status: "processing",
        sync_message: "Importando leads externos, página #{page}.",
        total_count: total,
        current_page: page
      )

      counters = process_rows(integration, rows)
      integration.increment!(:imported_count, counters[:created])
      integration.increment!(:updated_count, counters[:updated] + counters[:duplicate])
      integration.increment!(:failed_count, counters[:failed])

      if next_page?(page, total, rows.size)
        self.class.perform_later(integration.id, page + 1)
      else
        integration.update!(
          sync_status: "completed",
          sync_message: "Importação histórica concluída.",
          last_backfill_at: Time.current,
          last_cursor_at: Time.current,
          current_page: page
        )
      end
    rescue => e
      integration&.update(
        sync_status: "failed",
        sync_message: "Falha na importação histórica.",
        last_error_message: "#{e.class}: #{e.message}"
      )
      raise
    end

    private

    def process_rows(integration, rows)
      counters = Hash.new(0)

      rows.each do |row|
        result = ExternalLeadMigration::LeadUpsert.call(integration:, payload: row, historical: true)
        counters[result.action] += 1
      rescue => e
        counters[:failed] += 1
        Rails.logger.warn("[ExternalLeadMigration Backfill] tenant_id=#{integration.tenant_id} erro=#{e.class}: #{e.message}")
      end

      counters
    end

    def next_page?(page, total, returned)
      return false if returned.zero?
      return true if total.zero?

      page * PER_PAGE < total
    end
  end
end
