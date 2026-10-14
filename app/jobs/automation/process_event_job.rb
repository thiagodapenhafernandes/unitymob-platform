module Automation
  class ProcessEventJob < ApplicationJob
    queue_as :default

    def perform(automation_event_id)
      event = AutomationEvent.includes(:lead).find_by(id: automation_event_id)
      return unless event&.lead
      return unless event.tenant_id == event.lead.tenant_id

      Current.set(tenant: event.tenant) do
        event.with_lock do
          return if event.processed? || event.ignored?
          if %w[automation_tick automation_backfill].include?(event.source) && event.payload_hash[:workflow_id].present?
            workflow = event.tenant.automation_workflows.find_by(id: event.payload_hash[:workflow_id])
            return if workflow&.status == "paused"
          end

          event.mark_processing!
          Automation::Dispatcher.process_event(event)
          event.mark_processed!
        end
      end
    rescue => e
      event&.mark_failed!(e.message)
      raise
    end
  end
end
