module Leads
  class Acceptance
    def self.call(tenant:, lead:, actor:, metadata:, claim_statuses: nil, rule_ids: nil)
      previous_tenant = Current.tenant
      return :ineligible unless tenant && lead.tenant_id == tenant.id && actor&.tenant_id == tenant.id
      Current.tenant = tenant
      lead.with_lock do
        if lead.admin_user_id.nil?
          return :ineligible unless claim_statuses
          return :taken unless Lead.claim_unassigned!(lead.id, actor.id, statuses: claim_statuses, rule_ids: rule_ids)

          lead.reload
          lead.distribution_rule&.mark_agent_served!(actor.id)
        else
          return :taken unless lead.admin_user_id == actor.id
          return :already_accepted unless Lead.status_value(lead.status) == Lead.status_value(:waiting_acceptance)
          return :ineligible unless lead.update(status: Lead.status_value(:em_atendimento))
        end
        lead.activities.create!(kind: "accepted", metadata: metadata.compact)
      end
      :accepted
    ensure
      Current.tenant = previous_tenant if defined?(previous_tenant)
    end
  end
end
