module Automation
  # Executa as ações de uma regra sobre um lead. Suporta "esperar X dias" (nutrição),
  # agendando a continuação via solid_queue.
  class ActionRunner
    MAX_DEPTH = 3

    def self.run(rule, lead, from: 0, automation_event: nil)
      new(rule, lead, automation_event: automation_event).run(from)
    end

    def initialize(rule, lead, automation_event: nil)
      @rule = rule
      @lead = lead
      @automation_event = automation_event
      @log = []
      @executor = Automation::ActionExecutor.new(lead, automation_event: automation_event)
    end

    def run(from = 0)
      Thread.current[:automation_depth] = (Thread.current[:automation_depth] || 0) + 1
      actions = @rule.action_list
      i = from
      scheduled = false

      while i < actions.size
        action = actions[i]
        if action[:type] == "wait"
          schedule_continuation(i + 1, action[:days].to_i)
          scheduled = true
          break
        end
        execute(action)
        i += 1
      end

      @rule.register_run! if from.zero?
      record_run(scheduled ? "scheduled" : "executed")
    rescue => e
      Rails.logger.error("[automation] #{e.class}: #{e.message}")
      record_run("error", error: e.message)
    ensure
      Thread.current[:automation_depth] = [Thread.current[:automation_depth].to_i - 1, 0].max
    end

    private

    def record_run(status, error: nil)
      AutomationRun.create!(
        automation_rule: @rule,
        lead: @lead,
        automation_event: @automation_event,
        status: status,
        executed_at: Time.current,
        result: { actions: @log, error: error }.compact
      )
    end

    def execute(action)
      @executor.execute(action)
      @log << @rule.action_label(action)
    end

    def schedule_continuation(next_index, days)
      days = 1 if days <= 0
      Automation::RunActionsJob.set(wait: days.days).perform_later(@rule.id, @lead&.id, next_index, @automation_event&.id)
    end
  end
end
