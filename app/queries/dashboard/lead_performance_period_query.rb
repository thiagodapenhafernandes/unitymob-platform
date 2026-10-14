module Dashboard
  class LeadPerformancePeriodQuery
    def initialize(scope:, starts_at:, ends_at:)
      @scope = scope
      @window = starts_at..ends_at
    end

    def call
      pool_acceptances = LeadActivity.where(lead_id: @scope.reorder(nil).select(:id), kind: "accepted", created_at: @window)
        .where(<<~SQL.squish)
          lead_activities.metadata ->> 'shark_tank' = 'true' OR EXISTS (
            SELECT 1 FROM lead_activities pool_entry
            WHERE pool_entry.lead_id = lead_activities.lead_id
              AND pool_entry.kind = 'pocket_pool_ready'
              AND pool_entry.created_at <= lead_activities.created_at
          )
        SQL
      @scope.where(leads: { created_at: @window }).or(@scope.where(id: pool_acceptances.select(:lead_id)))
    end
  end
end
