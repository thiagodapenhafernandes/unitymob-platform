module Whatsapp
  class CampaignAudiencePreview
    Result = Struct.new(:total, :valid_phone_count, :without_phone_count, :sample, :filters, keyword_init: true)

    def self.call(filters:, tenant: Current.tenant)
      new(filters, tenant: tenant).call
    end

    def initialize(filters, tenant:)
      @filters = filters.to_h.with_indifferent_access
      @tenant = tenant
      raise ArgumentError, "Tenant obrigatório para preview de audiência WhatsApp" if @tenant.blank?
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

    attr_reader :filters, :tenant

    def base_scope
      scope = tenant.leads
      scope = scope.where(status: Lead.status_value(filters[:status])) if filters[:status].present?
      scope = scope.where("origin ILIKE ?", filters[:origin].to_s) if filters[:origin].present?
      scope = scope.where(admin_user_id: filters[:admin_user_id]) if filters[:admin_user_id].present?
      scope.distinct
    end
  end
end
