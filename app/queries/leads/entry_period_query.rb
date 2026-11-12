module Leads
  class EntryPeriodQuery
    def initialize(scope:, starts_at: nil, ends_at: nil)
      @scope = scope
      @window = starts_at..ends_at if starts_at || ends_at
    end

    def call
      return @scope unless @window

      local = @scope.where("NOT (#{mirrored_sql})")
      mirrored = @scope.where(mirrored_sql)
      mirrored = mirrored.where("#{source_date_sql} >= ?", @window.begin) if @window.begin
      mirrored = mirrored.where("#{source_date_sql} <= ?", @window.end) if @window.end
      local.where(leads: {created_at: @window}).or(local.where(id: inquiries.select(:lead_id))).or(mirrored)
    end

    def date_sql(fallback: nil)
      latest = LeadActivity.where(kind: "inquiry_complemented")
        .where("lead_activities.lead_id = leads.id AND lead_activities.tenant_id = leads.tenant_id")
      latest = latest.where(created_at: @window) if @window
      local = fallback || "GREATEST(leads.created_at, (#{latest.select('MAX(lead_activities.created_at)').to_sql}))"
      "CASE WHEN #{mirrored_sql} THEN #{source_date_sql} ELSE #{local} END"
    end

    def load_dates(records)
      dates = @scope.where(id: records.map(&:id)).reorder(nil).pluck(:id, Arel.sql(date_sql)).to_h
      records.each { |lead| lead.entry_received_at = dates[lead.id]&.in_time_zone || lead.created_at }
      records
    end

    private

    def mirrored_sql
      integration = ExternalLeadIntegration.where("external_lead_integrations.id = leads.external_lead_integration_id AND external_lead_integrations.tenant_id = leads.tenant_id")
        .where("operational_mappings ->> 'mirror_c2s_owners' IN (?)", %w[true 1 t on])
      "EXISTS (#{integration.select('1').to_sql})"
    end

    def source_date_sql
      epoch = "leads.other_information ->> 'c2s_source_created_at_epoch'"
      # Somente epoch validado na importação; metadados antigos usam o cadastro original.
      "COALESCE(CASE WHEN (#{epoch}) ~ '^[1-9][0-9]{9}$' THEN to_timestamp((#{epoch})::bigint) AT TIME ZONE 'UTC' END, leads.created_at)"
    end

    def inquiries
      scope = LeadActivity.joins(:lead).where(lead_id: @scope.reorder(nil).select(:id), kind: "inquiry_complemented")
        .where("lead_activities.tenant_id = leads.tenant_id")
      @window ? scope.where(created_at: @window) : scope
    end
  end
end
