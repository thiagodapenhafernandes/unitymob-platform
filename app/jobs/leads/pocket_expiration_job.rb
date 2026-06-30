module Leads
  class PocketExpirationJob < ApplicationJob
    queue_as :default

    def perform(lead_id, expected_admin_user_id = nil, tenant_id: nil)
      tenant = Tenant.find_by(id: tenant_id) || Current.tenant
      lead = tenant.present? ? tenant.leads.find_by(id: lead_id) : Lead.find_by(id: lead_id)
      return if lead.blank?

      tenant ||= lead.tenant
      result = Current.set(tenant: tenant) do
        Leads::PocketExpirationService.expire!(
          lead,
          expected_admin_user_id: expected_admin_user_id,
          source: "scheduled"
        )
      end

      Rails.logger.info "[PocketExpirationJob] lead=#{lead_id} result=#{result}"
    end
  end
end
