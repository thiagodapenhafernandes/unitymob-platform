module Automation
  class RunActionsJob < ApplicationJob
    queue_as :default

    def perform(rule_id, lead_id, from = 0)
      rule = AutomationRule.find_by(id: rule_id)
      lead = Lead.find_by(id: lead_id)
      return unless rule&.active? && lead

      Automation::ActionRunner.run(rule, lead, from: from)
    end
  end
end
