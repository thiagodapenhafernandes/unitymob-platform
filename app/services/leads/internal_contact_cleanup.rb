module Leads
  class InternalContactCleanup
    Result = Struct.new(:tenant_id, :tenant_name, :matched_count, :removed_count, :leads, keyword_init: true)

    def self.call(tenant: nil, execute: false, logger: Rails.logger)
      new(tenant:, execute:, logger:).call
    end

    def initialize(tenant: nil, execute: false, logger: Rails.logger)
      @tenant = tenant
      @execute = execute
      @logger = logger
    end

    def call
      tenants.map { |tenant| cleanup_tenant(tenant) }
    end

    private

    attr_reader :tenant, :execute, :logger

    def tenants
      return Array(tenant) if tenant.present?

      Tenant.order(:id)
    end

    def cleanup_tenant(tenant)
      phones = internal_phones_for(tenant)
      leads = phones.empty? ? [] : matching_leads(tenant, phones).to_a
      removed = 0

      if execute && leads.any?
        leads.each do |lead|
          lead.destroy!
          removed += 1
        end
      end

      Result.new(
        tenant_id: tenant.id,
        tenant_name: tenant.name,
        matched_count: leads.size,
        removed_count: removed,
        leads: leads.map { |lead| lead_snapshot(lead) }
      )
    end

    def internal_phones_for(tenant)
      tenant.admin_users
        .account_members
        .pluck(:phone, :secondary_phone)
        .flatten
        .filter_map { |phone| Phones::Normalizer.call(phone).to_s.presence }
        .uniq
    end

    def matching_leads(tenant, phones)
      tenant.leads.where(
        "regexp_replace(coalesce(leads.phone, ''), '\\D', '', 'g') IN (:phones) OR regexp_replace(coalesce(leads.client_phone, ''), '\\D', '', 'g') IN (:phones)",
        phones: phones
      ).order(:id)
    end

    def lead_snapshot(lead)
      {
        id: lead.id,
        name: lead.display_name.presence || lead.name,
        phone: lead.display_phone.presence || lead.phone,
        origin: lead.origin,
        admin_user_id: lead.admin_user_id,
        created_at: lead.created_at
      }
    end
  end
end
