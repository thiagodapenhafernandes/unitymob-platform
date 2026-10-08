module Leads
  class ContingencySweepJob < ApplicationJob
    queue_as :default

    def perform
      Tenant.find_each do |tenant|
        Current.set(tenant: tenant) do
          rules = tenant.distribution_rules.where(contingency_enabled: true).select(:id)
          scope = tenant.leads.where(contingency_pending: true)
            .or(tenant.leads.where(distribution_rule_id: rules))
          if LeadSetting.instance(tenant: tenant).default_distribution_rule_id.present?
            scope = scope.or(tenant.leads.where(distribution_rule_id: nil, admin_user_id: nil))
          end
          scope.where("contingency_pending = ? OR admin_user_id IS NULL OR status = ?", true, Lead.status_value(:waiting_acceptance))
            .where(archived_at: nil).where.not(status: Lead.non_operational_status_values(tenant: tenant))
            .find_each do |lead|
            ContingencyService.check!(lead)
          rescue => e
            Rails.logger.warn("[ContingencySweepJob] tenant=#{tenant.id} lead=#{lead.id} error=#{e.class}")
          end
        end
      end
    end
  end
end
