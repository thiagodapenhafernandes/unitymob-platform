module Automation
  class WorkflowRunner
    MAX_STEPS = 50

    def self.start(workflow, lead, event:, automation_event: nil)
      return unless workflow&.active_version && lead

      key = idempotency_key(workflow, workflow.active_version, lead, event, automation_event: automation_event)
      execution = AutomationExecution.find_or_initialize_by(idempotency_key: key)
      if execution.persisted?
        if %w[failed canceled].include?(execution.status)
          execution.update!(
            status: "pending",
            current_node_id: nil,
            failed_at: nil,
            error_message: nil
          )
          Automation::RunWorkflowJob.perform_later(execution.id)
        end
        return execution
      end

      execution.assign_attributes(
        automation_workflow: workflow,
        automation_workflow_version: workflow.active_version,
        lead: lead,
        automation_event: automation_event,
        status: "pending",
        context: {
          "event" => event.to_s,
          "automation_event_id" => automation_event&.id,
          "automation_event_source" => automation_event&.source
        }.compact
      )
      execution.save!
      Automation::RunWorkflowJob.perform_later(execution.id)
      execution
    end

    def self.run(execution, from_node_id: nil)
      new(execution).run(from_node_id: from_node_id)
    end

    def self.idempotency_key(workflow, version, lead, event, automation_event: nil)
      if automation_event
        return "workflow:#{workflow.id}:version:#{version.id}:automation_event:#{automation_event.id}"
      end

      "workflow:#{workflow.id}:version:#{version.id}:lead:#{lead.id}:event:#{event}"
    end

    def initialize(execution)
      @execution = execution
      @workflow = execution.automation_workflow
      @version = execution.automation_workflow_version
      @lead = execution.lead
      @definition = @version.definition_hash
      @executor = Automation::ActionExecutor.new(@lead)
    end

    def run(from_node_id: nil)
      Thread.current[:automation_depth] = (Thread.current[:automation_depth] || 0) + 1
      @execution.update!(status: "running", started_at: @execution.started_at || Time.current)

      queue = [from_node_id.present? ? node_by_id(from_node_id) : entry_node].compact
      count = 0
      waiting = false

      while queue.any? && count < MAX_STEPS
        node = queue.shift
        count += 1
        result = execute_node(node)
        if result == :waiting
          waiting = true
          next
        end
        next if result == :completed

        queue.concat(next_nodes(node))
      end

      if count >= MAX_STEPS
        fail_execution!("Acompanhamento interrompido por limite de #{MAX_STEPS} etapas.")
      elsif waiting
        @execution.update!(status: "waiting")
      else
        @execution.update!(status: "completed", current_node_id: nil, finished_at: Time.current)
      end
    rescue => e
      Rails.logger.error("[automation workflow] #{e.class}: #{e.message}\n#{Array(e.backtrace).first(8).join("\n")}")
      fail_execution!(e.message)
    ensure
      Thread.current[:automation_depth] = [Thread.current[:automation_depth].to_i - 1, 0].max
    end

    private

    def execute_node(node)
      step = @execution.steps.create!(
        node_id: node[:id],
        node_type: node[:type],
        status: "running",
        started_at: Time.current,
        input: { "config" => node[:config] || {} }
      )

      case node[:type].to_s
      when "entry", "condition", "branch"
        matched = node[:type].to_s == "condition" ? condition_matched?(node) : true
        complete_step(step, output: { "matched" => matched })
        unless matched
          return :completed
        end
      when "action"
        action = Automation::WorkflowActionAdapter.to_action(node)
        begin
          @executor.execute(action)
        rescue => e
          return schedule_action_retry(step, node, e) if retry_action?(node)

          raise
        end
        complete_step(step, output: { "action" => action, "label" => Automation::ActionExecutor.label(action) })
        if stop_after_node?(node)
          return :completed
        end
      when "wait"
        schedule_wait(step, node)
        :waiting
      when "await_event"
        schedule_await_event(step, node)
        :waiting
      when "exit"
        complete_step(step)
        :completed
      else
        complete_step(step, status: "skipped", output: { "reason" => "unsupported_node_type" })
      end
    rescue => e
      step&.update!(status: "failed", finished_at: Time.current, error_message: e.message)
      raise
    end

    def schedule_wait(step, node)
      scheduled_for = Automation::ScheduleCalculator.wait_until(node[:config] || {})
      next_ids = next_nodes(node).filter_map { |item| item[:id] }

      step.update!(
        status: "waiting",
        scheduled_for: scheduled_for,
        output: {
          "resume_node_id" => next_ids.first,
          "resume_node_ids" => next_ids,
          "wait_mode" => (node[:config] || {})[:mode].presence || "duration"
        }
      )
      @execution.update!(status: "waiting", current_node_id: node[:id])

      schedule_resume_jobs(scheduled_for, next_ids)
    end

    def schedule_await_event(step, node)
      config = (node[:config] || {}).with_indifferent_access
      scheduled_for = Automation::ScheduleCalculator.wait_until({
        "mode" => "duration",
        "amount" => config[:timeout_amount].presence || config[:amount].presence || 1,
        "unit" => config[:timeout_unit].presence || config[:unit].presence || "days"
      })
      next_ids = next_nodes(node).filter_map { |item| item[:id] }

      step.update!(
        status: "waiting",
        scheduled_for: scheduled_for,
        output: {
          "resume_node_id" => next_ids.first,
          "resume_node_ids" => next_ids,
          "await_event" => config[:trigger],
          "timeout_at" => scheduled_for
        }
      )
      @execution.update!(status: "waiting", current_node_id: node[:id])

      schedule_resume_jobs(scheduled_for, next_ids)
    end

    def schedule_resume_jobs(scheduled_for, next_ids)
      ids = Array(next_ids).reject(&:blank?)
      if ids.any?
        ids.each do |next_id|
          Automation::RunWorkflowJob.set(wait_until: scheduled_for).perform_later(@execution.id, next_id)
        end
      else
        Automation::RunWorkflowJob.set(wait_until: scheduled_for).perform_later(@execution.id)
      end
    end

    def schedule_action_retry(step, node, error)
      config = (node[:config] || {}).with_indifferent_access
      attempts = retry_attempts_for(node[:id]) + 1
      max_attempts = [config[:retry_attempts].to_i, 1].max
      raise error if attempts > max_attempts

      scheduled_for = Automation::ScheduleCalculator.wait_until({
        "mode" => "duration",
        "amount" => config[:retry_delay_amount].presence || 15,
        "unit" => config[:retry_delay_unit].presence || "minutes"
      })

      store_retry_attempt(node[:id], attempts)
      step.update!(
        status: "waiting",
        scheduled_for: scheduled_for,
        error_message: error.message,
        output: {
          "retry_node_id" => node[:id],
          "retry_attempt" => attempts,
          "retry_max_attempts" => max_attempts
        }
      )
      @execution.update!(status: "waiting", current_node_id: node[:id])
      Automation::RunWorkflowJob.set(wait_until: scheduled_for).perform_later(@execution.id, node[:id])
      :waiting
    end

    def complete_step(step, status: "completed", output: {})
      step.update!(status: status, output: output, finished_at: Time.current)
    end

    def fail_execution!(message)
      @execution.update!(
        status: "failed",
        failed_at: Time.current,
        error_message: message
      )
    end

    def condition_matched?(node)
      config = (node[:config] || {}).with_indifferent_access
      checks = []

      if config[:stage].present?
        checks << (Lead.status_value(@lead.status) == Lead.status_value(config[:stage]))
      end

      if config[:source].present?
        checks << @lead.origin.to_s.casecmp?(config[:source].to_s)
      end

      return true if checks.empty?

      config[:operator].to_s == "or" ? checks.any? : checks.all?
    end

    def stop_after_node?(node)
      ActiveModel::Type::Boolean.new.cast((node[:config] || {})[:stop_flow])
    end

    def retry_action?(node)
      ActiveModel::Type::Boolean.new.cast((node[:config] || {})[:retry_enabled])
    end

    def retry_attempts_for(node_id)
      @execution.context.to_h.dig("retries", node_id.to_s).to_i
    end

    def store_retry_attempt(node_id, attempts)
      context = @execution.context.to_h.deep_dup
      context["retries"] ||= {}
      context["retries"][node_id.to_s] = attempts
      @execution.update!(context: context)
    end

    def entry_node
      nodes.find { |node| node[:type].to_s == "entry" }
    end

    def next_nodes(node)
      edges
        .select { |item| item[:from].to_s == node[:id].to_s }
        .filter_map { |edge| node_by_id(edge[:to]) }
    end

    def node_by_id(id)
      nodes.find { |node| node[:id].to_s == id.to_s }
    end

    def nodes
      @nodes ||= Array(@definition[:nodes]).map(&:with_indifferent_access)
    end

    def edges
      @edges ||= Array(@definition[:edges]).map(&:with_indifferent_access)
    end
  end
end
