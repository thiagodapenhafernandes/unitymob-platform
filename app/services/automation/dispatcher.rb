module Automation
  # Dispara regras casadas para um evento (event-driven). Enfileira a execução.
  class Dispatcher
    def self.dispatch(event, lead, source: "platform", payload: {}, idempotency_key: nil, async: true)
      return if lead.nil?

      Automation::EventBus.emit(
        event,
        lead: lead,
        source: source,
        payload: payload,
        idempotency_key: idempotency_key,
        async: async
      )
    rescue => e
      Rails.logger.warn("[automation event] #{e.class}: #{e.message}")
    end

    def self.process_event(automation_event)
      new(automation_event).process
    end

    def initialize(automation_event)
      @automation_event = automation_event
      @event = automation_event.name.to_s
      @lead = automation_event.lead
    end

    def process
      return if @lead.nil?
      # Loop-breaker: ações que mudam o lead não devem reentrar infinitamente.
      return if (Thread.current[:automation_depth] || 0) >= Automation::ActionRunner::MAX_DEPTH

      AutomationRule.for_event(@event).ordered.find_each do |rule|
        next unless Automation::ConditionMatcher.match?(rule, @lead)

        Automation::RunActionsJob.perform_later(rule.id, @lead.id, 0, @automation_event.id)
      end

      Automation::WorkflowDispatcher.dispatch_event(@automation_event)
    rescue => e
      Rails.logger.warn("[automation dispatch] #{e.class}: #{e.message}")
    end
  end
end
