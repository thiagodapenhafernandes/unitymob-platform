module Leads
  class PoolRenotifyJob < ApplicationJob
    queue_as :default

    def perform(lead_id, tenant_id: nil)
      tenant = Tenant.find_by(id: tenant_id) || Current.tenant
      raise ArgumentError, "Tenant obrigatório para renotificar Bolsão" unless tenant

      Current.set(tenant: tenant) do
        lead = tenant.leads.includes(:distribution_rule).find_by(id: lead_id)
        return unless pool_open?(lead)

        rule = lead.distribution_rule
        Leads::NotificationDispatcher.notify_pool(lead, rule, candidates: rule.candidates_filtered_by_checkin, context: "pool_renotify")
        lead.activities.create!(
          kind: "pool_renotified",
          metadata: {
            rule_id: rule.id,
            rule_name: rule.name,
            interval_minutes: rule.pool_renotify_minutes_value
          }
        )
        self.class.set(wait: rule.pool_renotify_minutes_value.minutes).perform_later(lead.id, tenant_id: tenant.id) if pool_open?(lead.reload)
      end
    end

    private

    def pool_open?(lead)
      lead.present? &&
        lead.admin_user_id.blank? &&
        lead.distribution_rule&.pool_renotify_interval? &&
        Lead.status_value(lead.status) == Lead.status_value(:waiting_acceptance)
    end
  end
end
