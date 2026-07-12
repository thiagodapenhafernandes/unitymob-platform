module Leads
  class PocketExpirationJob < ApplicationJob
    queue_as :default

    def perform(lead_id, expected_admin_user_id = nil, tenant_id: nil)
      tenant = Tenant.find_by(id: tenant_id) || Current.tenant
      raise ArgumentError, "Tenant obrigatório para expirar lead da carteira" unless tenant
      lead = tenant.leads.find_by(id: lead_id)
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
