module Whatsapp
  class CampaignAudiencePreview
    Result = Struct.new(:total, :valid_phone_count, :without_phone_count, :sample, :filters, keyword_init: true)

    def self.call(filters:)
      new(filters).call
    end

    def initialize(filters)
      @filters = filters.to_h.with_indifferent_access
    end

    def call
      scoped = base_scope
      valid = scoped.where.not(phone: [nil, ""])

      Result.new(
        total: scoped.count,
        valid_phone_count: valid.count,
        without_phone_count: scoped.where(phone: [nil, ""]).count,
        sample: valid.includes(:admin_user).order(created_at: :desc).limit(8).to_a,
        filters: filters.compact
      )
    end

    private

    attr_reader :filters

    def base_scope
      scope = Lead.all
      scope = scope.where(status: Lead.status_value(filters[:status])) if filters[:status].present?
      scope = scope.where("origin ILIKE ?", filters[:origin].to_s) if filters[:origin].present?
      scope = scope.where(admin_user_id: filters[:admin_user_id]) if filters[:admin_user_id].present?
      scope.distinct
    end
  end
end
