module DistributionRules
  class AutoUpdateAgentsFromCheckinJob < ApplicationJob
    queue_as :checkin

    def perform(check_in_id)
      return unless CheckIn.column_names.include?("status_chegada")
      return unless DistributionRule.column_names.include?("auto_update_agents_enabled")
      return unless DistributionRule.column_names.include?("auto_update_trigger")

      check_in = CheckIn.includes(:store).find_by(id: check_in_id)
      return if check_in.blank? || check_in.store.blank?
      return if check_in.tenant.blank?
      return if check_in.status_chegada.blank?

      Current.set(tenant: check_in.tenant) do
        rules = check_in.tenant.distribution_rules
                        .where(active: true, auto_update_agents_enabled: true)
                        .where("? = ANY(checkin_store_ids)", check_in.store_id)
                        .where("? = ANY(auto_update_trigger)", check_in.status_chegada)

        rules.find_each do |rule|
          rule.update_agents_from_store_checkin!(
            status: check_in.status_chegada,
            date: check_in.checked_in_at.to_date
          )
        rescue StandardError => e
          Rails.logger.warn("[DistributionRules::AutoUpdateAgentsFromCheckinJob] rule_id=#{rule.id} skipped: #{e.class}: #{e.message}")
        end
      end
    end
  end
end
