module Automation
  class ProcessEventJob < ApplicationJob
    queue_as :default

    def perform(automation_event_id)
      event = AutomationEvent.includes(:lead).find_by(id: automation_event_id)
      return unless event&.lead
      return if event.processed? || event.ignored?

      event.mark_processing!
      Automation::Dispatcher.process_event(event)
      event.mark_processed!
    rescue => e
      event&.mark_failed!(e.message)
      raise
    end
  end
end
