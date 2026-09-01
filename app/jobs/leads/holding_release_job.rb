module Leads
  class HoldingReleaseJob < ApplicationJob
    queue_as :default

    BATCH_LIMIT = 200

    def perform
      Tenant.find_each do |tenant|
        Current.set(tenant: tenant) do
          tenant.leads.represado
                .where(admin_user_id: nil)
                .where.not(distribution_rule_id: nil)
                .includes(:distribution_rule)
                .limit(BATCH_LIMIT)
                .find_each { |lead| release_lead(lead) }
        end
      rescue => e
        Rails.logger.warn("[HoldingReleaseJob] falha ao varrer tenant #{tenant.id}: #{e.class} #{e.message}")
      end
    end

    private

    def release_lead(lead)
      rule = lead.distribution_rule
      return unless rule&.active?
      return unless rule.represamento_active?
      return if rule.outside_represamento_hours?
      return unless held_by_operating_hours?(lead)

      Current.set(tenant: lead.tenant) do
        Leads::DistributorService.distribute_to(lead, rule)
      end
    rescue => e
      Rails.logger.warn("[HoldingReleaseJob] falha ao liberar lead #{lead.id}: #{e.class} #{e.message}")
    end

    def held_by_operating_hours?(lead)
      last_dammed = lead.activities.where(kind: "dammed").order(created_at: :desc).first
      return false if last_dammed.blank?

      last_dammed.metadata["reason"].blank?
    end
  end
end
