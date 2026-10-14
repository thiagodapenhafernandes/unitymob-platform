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
      tenant = @lead&.tenant || @rule.tenant || Current.tenant
      raise ArgumentError, "Tenant obrigatório para executar automação" if tenant.blank?

      Current.set(tenant: tenant) do
        Thread.current[:automation_depth] = (Thread.current[:automation_depth] || 0) + 1
        @from = from.to_i
        if @automation_event
          @run = @rule.automation_runs.where(lead: @lead, automation_event: @automation_event)
            .where("COALESCE(result ->> 'from', '0') = ?", @from.to_s).order(:id).last
          return if @run && %w[executed scheduled].include?(@run.status)
        end
        @run ||= @rule.automation_runs.create!(lead: @lead, automation_event: @automation_event,
          status: "running", result: { from: @from, next_index: @from, actions: [] })
        @log = Array(@run.result["actions"])
        actions = @rule.action_list
        i = (@run.result["next_index"] || @from).to_i
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
          @run.update!(result: { from: @from, next_index: i, actions: @log })
        end

        @rule.register_run! if from.zero?
        record_run(scheduled ? "scheduled" : "executed")
      end
    rescue => e
      Rails.logger.error("[automation] #{e.class}: #{e.message}")
      record_run("error", error: e.message)
    ensure
      Thread.current[:automation_depth] = [Thread.current[:automation_depth].to_i - 1, 0].max
    end

    private

    def record_run(status, error: nil)
      @run&.update!(status: status, executed_at: Time.current,
                    result: @run.result.merge("actions" => @log, "error" => error).compact)
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
