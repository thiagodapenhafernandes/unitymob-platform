module Automation
  class RunActionsJob < ApplicationJob
    queue_as :default

    def perform(rule_id, lead_id, from = 0, automation_event_id = nil)
      rule = AutomationRule.find_by(id: rule_id)
      lead = Lead.find_by(id: lead_id)
      automation_event = AutomationEvent.find_by(id: automation_event_id) if automation_event_id.present?
      return unless rule&.active? && lead

      Automation::ActionRunner.run(rule, lead, from: from, automation_event: automation_event)
    end
  end
end
