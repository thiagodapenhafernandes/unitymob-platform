module Leads
  class EntryPeriodQuery
    def initialize(scope:, starts_at: nil, ends_at: nil)
      @scope = scope
      @window = starts_at..ends_at if starts_at || ends_at
    end

    def call
      return @scope unless @window

      @scope.where(leads: {created_at: @window}).or(@scope.where(id: inquiries.select(:lead_id)))
    end

    def date_sql
      latest = LeadActivity.where(kind: "inquiry_complemented")
        .where("lead_activities.lead_id = leads.id AND lead_activities.tenant_id = leads.tenant_id")
      latest = latest.where(created_at: @window) if @window
      "GREATEST(leads.created_at, (#{latest.select('MAX(lead_activities.created_at)').to_sql}))"
    end

    def load_dates(records)
      dates = inquiries.where(lead_id: records.map(&:id)).group(:lead_id).maximum(:created_at)
      records.each { |lead| lead.entry_received_at = [lead.created_at, dates[lead.id]].compact.max }
      records
    end

    private

    def inquiries
      scope = LeadActivity.joins(:lead).where(lead_id: @scope.reorder(nil).select(:id), kind: "inquiry_complemented")
        .where("lead_activities.tenant_id = leads.tenant_id")
      @window ? scope.where(created_at: @window) : scope
    end
  end
end
