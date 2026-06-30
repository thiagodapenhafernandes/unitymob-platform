module Automation
  class WorkflowRunner
    MAX_STEPS = 50

    def self.start(workflow, lead, event:, automation_event: nil)
      return unless workflow&.active_version
      return unless workflow.tenant_id == lead&.tenant_id
      return if automation_event.present? && automation_event.tenant_id != workflow.tenant_id

      key = idempotency_key(workflow, workflow.active_version, lead, event, automation_event: automation_event)
      execution = workflow.tenant.automation_executions.find_or_initialize_by(idempotency_key: key)
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
        tenant: workflow.tenant,
        automation_workflow: workflow,
        automation_workflow_version: workflow.active_version,
        lead: lead,
        automation_event: automation_event,
        status: "pending",
        context: {
          "event" => event.to_s,
          "automation_event_id" => automation_event&.id,
          "automation_event_source" => automation_event&.source
        }.compact.merge(initial_response_context(event, automation_event))
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

      lead_key = lead ? "lead:#{lead.id}" : "lead:none"
      "workflow:#{workflow.id}:version:#{version.id}:#{lead_key}:event:#{event}"
    end

    def self.initial_response_context(event, automation_event)
      return {} unless automation_event
      return {} unless %w[whatsapp_received whatsapp_campaign_message_replied].include?(event.to_s)

      payload = automation_event.payload_hash
      body = payload[:message_body].presence ||
             payload[:button_text].presence ||
             payload.dig(:recipient, :message_body).presence
      {
        "whatsapp_response" => {
          "event_id" => automation_event.id,
          "event" => event.to_s,
          "payload" => payload.to_h,
          "body" => body.to_s,
          "lead_status" => automation_event.lead&.status,
          "received_at" => Time.current.iso8601
        }
      }
    end

    def initialize(execution)
      @execution = execution
      @workflow = execution.automation_workflow
      @version = execution.automation_workflow_version
      @lead = execution.lead
      @definition = @version.definition_hash
      @executor = Automation::ActionExecutor.new(@lead, automation_event: execution.automation_event)
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
      when "await_whatsapp_response"
        schedule_await_whatsapp_response(step, node)
        :waiting
      when "response_condition"
        matched = response_condition_matched?(node)
        record_response_condition_match(node) if matched
        complete_step(step, output: { "matched" => matched, "response_event_id" => whatsapp_response_context.with_indifferent_access[:event_id] })
        unless matched
          return :completed
        end
      when "response_fallback"
        matched = response_fallback_matched?(node)
        complete_timed_out_response_waits if matched && (node[:config] || {})[:fallback_type].to_s == "timeout"
        complete_step(step, output: { "matched" => matched, "fallback_type" => (node[:config] || {})[:fallback_type].presence || "no_match" })
        unless matched
          return :completed
        end
      when "response_router"
        if (route_match = response_route_match_for(node))
          actions = Array(route_match["actions"])
          actions.each { |action| @executor.execute(action) }
          clear_response_route_match(node[:id])
          complete_step(
            step,
            output: {
              "matched_route_id" => route_match["route_id"],
              "matched_route_label" => route_match["route_label"],
              "actions_count" => actions.size
            }
          )
        else
          schedule_response_router(step, node)
          :waiting
        end
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

    def schedule_response_router(step, node)
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
          "await_event" => "whatsapp_received",
          "response_router" => true,
          "timeout_at" => scheduled_for
        }
      )
      @execution.update!(status: "waiting", current_node_id: node[:id])

      schedule_resume_jobs(scheduled_for, next_ids)
    end

    def schedule_await_whatsapp_response(step, node)
      config = (node[:config] || {}).with_indifferent_access
      scheduled_for = Automation::ScheduleCalculator.wait_until({
        "mode" => "duration",
        "amount" => config[:timeout_amount].presence || config[:amount].presence || 1,
        "unit" => config[:timeout_unit].presence || config[:unit].presence || "days"
      })
      next_ids = next_nodes(node).filter_map { |item| item[:id] }
      timeout_next_ids = next_nodes(node)
        .select { |item| item[:type].to_s == "response_fallback" && (item[:config] || {})[:fallback_type].to_s == "timeout" }
        .filter_map { |item| item[:id] }

      step.update!(
        status: "waiting",
        scheduled_for: scheduled_for,
        output: {
          "resume_node_id" => next_ids.first,
          "resume_node_ids" => next_ids,
          "await_event" => "whatsapp_received",
          "await_whatsapp_response" => true,
          "timeout_at" => scheduled_for
        }
      )
      @execution.update!(status: "waiting", current_node_id: node[:id])

      schedule_resume_jobs(scheduled_for, timeout_next_ids.presence || next_ids)
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
        return false unless @lead
        checks << (Lead.status_value(@lead.status) == Lead.status_value(config[:stage]))
      end

      if config[:source].present?
        return false unless @lead
        checks << @lead.origin.to_s.casecmp?(config[:source].to_s)
      end

      return true if checks.empty?

      config[:operator].to_s == "or" ? checks.any? : checks.all?
    end

    def response_condition_matched?(node)
      response = whatsapp_response_context
      return false if response.blank?

      config = (node[:config] || {}).with_indifferent_access
      return button_payload_or_text_condition_matched?(config) if config[:match_strategy].to_s == "button_payload_or_text"

      value = response_value(config[:field])
      expected = config[:value].to_s.strip

      case config[:operator].to_s
      when "present"
        value.present?
      when "not_contains"
        expected.blank? || !value.to_s.downcase.include?(expected.downcase)
      when "contains"
        expected.blank? || value.to_s.downcase.include?(expected.downcase)
      else
        value.to_s.casecmp?(expected)
      end
    end

    def button_payload_or_text_condition_matched?(config)
      expected_payload = config[:button_payload].presence || config[:button_key].presence || config[:value].presence
      expected_text = config[:button_text].presence || config[:fallback_value].presence
      payload_value = response_value("interaction.button_payload")
      text_value = response_value("interaction.button_text")

      (expected_payload.present? && payload_value.to_s.casecmp?(expected_payload.to_s)) ||
        (expected_text.present? && text_value.to_s.casecmp?(expected_text.to_s))
    end

    def response_fallback_matched?(node)
      fallback_type = (node[:config] || {})[:fallback_type].to_s.presence || "no_match"
      response = whatsapp_response_context

      return response.blank? if fallback_type == "timeout"
      return false if response.blank?

      !sibling_response_condition_matched?(node)
    end

    def sibling_response_condition_matched?(fallback_node)
      incoming = edges.select { |edge| edge[:to].to_s == fallback_node[:id].to_s }.map { |edge| edge[:from].to_s }
      sibling_ids = edges
        .select { |edge| incoming.include?(edge[:from].to_s) }
        .map { |edge| edge[:to].to_s }
        .reject { |id| id == fallback_node[:id].to_s }

      sibling_ids.filter_map { |id| node_by_id(id) }
        .select { |node| node[:type].to_s == "response_condition" }
        .any? { |node| response_condition_matched?(node) }
    end

    def response_value(field)
      response = whatsapp_response_context.with_indifferent_access
      payload = (response[:payload] || {}).with_indifferent_access

      case field.to_s
      when "message.body"
        response[:body]
      when "interaction.button_text"
        payload.dig(:button, :title).presence ||
          payload.dig(:interactive, :button_reply, :title).presence ||
          payload[:button_text].presence ||
          response[:body]
      when "interaction.button_payload"
        payload.dig(:button, :id).presence ||
          payload.dig(:interactive, :button_reply, :id).presence ||
          payload[:button_payload].presence ||
          payload[:button_id]
      when "campaign.response_decision.action"
        payload.dig(:response_decision, :action)
      when "campaign.response_decision.label"
        payload.dig(:response_decision, :action_label)
      when "campaign.response_decision.distribution_rule_id"
        payload.dig(:response_decision, :distribution_rule_id)
      when "lead.status", "lead.lifecycle"
        @lead&.status
      when "guardrail.outside_hours"
        payload[:outside_hours]
      when "guardrail.crm_error"
        payload[:crm_error]
      else
        payload.dig(*field.to_s.split(".").map(&:to_sym))
      end
    end

    def whatsapp_response_context
      (@execution.context.to_h["whatsapp_response"] || {}).with_indifferent_access
    end

    def record_response_condition_match(node)
      context = @execution.context.to_h.deep_dup
      context["response_condition_matches"] ||= {}
      event_id = whatsapp_response_context[:event_id] || whatsapp_response_context["event_id"] || "latest"
      context["response_condition_matches"][event_id.to_s] ||= []
      context["response_condition_matches"][event_id.to_s] << node[:id].to_s
      @execution.update!(context: context)
    end

    def complete_timed_out_response_waits
      @execution.steps
        .where(status: "waiting", node_type: "await_whatsapp_response")
        .update_all(status: "completed", finished_at: Time.current, output: { "timeout" => true })
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

    def response_route_match_for(node)
      @execution.context.to_h.dig("response_router_matches", node[:id].to_s)
    end

    def clear_response_route_match(node_id)
      context = @execution.context.to_h.deep_dup
      context.dig("response_router_matches")&.delete(node_id.to_s)
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
