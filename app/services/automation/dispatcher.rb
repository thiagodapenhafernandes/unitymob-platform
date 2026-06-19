module Automation
  # Dispara regras casadas para um evento (event-driven). Enfileira a execução.
  class Dispatcher
    def self.dispatch(event, lead)
      return if lead.nil?
      # Loop-breaker: ações que mudam o lead não devem reentrar infinitamente.
      return if (Thread.current[:automation_depth] || 0) >= Automation::ActionRunner::MAX_DEPTH

      AutomationRule.for_event(event).ordered.find_each do |rule|
        next unless Automation::ConditionMatcher.match?(rule, lead)
        Automation::RunActionsJob.perform_later(rule.id, lead.id)
      end
    rescue => e
      Rails.logger.warn("[automation dispatch] #{e.class}: #{e.message}")
    end
  end
end
