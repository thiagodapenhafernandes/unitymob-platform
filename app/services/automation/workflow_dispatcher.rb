module Automation
  class WorkflowDispatcher
    def self.dispatch(event, lead)
      Automation::Dispatcher.dispatch(event, lead)
    end

    def self.dispatch_event(automation_event)
      new(automation_event.name, automation_event.lead, automation_event: automation_event).dispatch
    end

    def self.dispatch_idle_candidates(limit: 200)
      active_workflows_for_event("lead_idle").each do |workflow|
        Current.set(tenant: workflow.tenant) do
          entry = entry_node(workflow)
          idle_hours = entry.dig(:config, :idle_hours).to_i
          next unless idle_hours.positive?

          scope = workflow.tenant.leads.where("leads.updated_at <= ?", idle_hours.hours.ago)
          stage = entry.dig(:config, :stage)
          scope = scope.where(status: Lead.status_value(stage)) if stage.present?
          source = entry.dig(:config, :source)
          scope = scope.where("origin ILIKE ?", source) if source.present?
          distribution_rule_ids = distribution_rule_ids_for(entry.fetch(:config, {}))
          scope = scope.where(distribution_rule_id: distribution_rule_ids) if distribution_rule_ids.any?

          processed = AutomationExecution
            .where(tenant: workflow.tenant, automation_workflow_id: workflow.id)
            .where.not(lead_id: nil)
            .pluck(:lead_id)
            .uniq
          scope = scope.where.not(id: processed) if processed.any?

          scope.limit(limit).find_each do |lead|
            Automation::Dispatcher.dispatch(
              :lead_idle,
              lead,
              source: "automation_tick",
              payload: { workflow_id: workflow.id, idle_hours: idle_hours },
              idempotency_key: "lead_idle:workflow:#{workflow.id}:lead:#{lead.id}"
            )
          end
        end
      end
    end

    def self.dispatch_scheduled_routines(limit: 200)
      active_workflows_for_event("scheduled_routine").each do |workflow|
        Current.set(tenant: workflow.tenant) do
          entry = entry_node(workflow)
          config = entry.fetch(:config, {}).with_indifferent_access
          next unless Automation::ScheduleCalculator.recurring_due?(config)

          bucket = Automation::ScheduleCalculator.recurring_bucket(config)
          scope = workflow.tenant.leads
          stage = config[:stage]
          scope = scope.where(status: Lead.status_value(stage)) if stage.present?
          source = config[:source]
          scope = scope.where("origin ILIKE ?", source) if source.present?
          distribution_rule_ids = distribution_rule_ids_for(config)
          scope = scope.where(distribution_rule_id: distribution_rule_ids) if distribution_rule_ids.any?

          scope.limit(limit).find_each do |lead|
            Automation::Dispatcher.dispatch(
              :scheduled_routine,
              lead,
              source: "automation_tick",
              payload: { workflow_id: workflow.id, bucket: bucket },
              idempotency_key: "scheduled_routine:workflow:#{workflow.id}:lead:#{lead.id}:bucket:#{bucket}"
            )
          end
        end
      end
    end

    def self.active_workflows_for_event(event)
      scope = Current.tenant ? Current.tenant.automation_workflows : AutomationWorkflow
      scope.active.includes(:active_version).select do |workflow|
        entry_node(workflow).dig(:config, :trigger).to_s == event.to_s
      end
    end

    def self.entry_node(workflow)
      definition = workflow.active_version&.definition_hash || {}
      Array(definition[:nodes]).map(&:with_indifferent_access).find { |node| node[:type].to_s == "entry" } || {}
    end

    def initialize(event, lead, automation_event: nil)
      @event = event.to_s
      @lead = lead
      @automation_event = automation_event
    end

    def dispatch
      tenant = @lead&.tenant || @automation_event&.tenant || Current.tenant
      Current.set(tenant: tenant) do
        self.class.active_workflows_for_event(@event).each do |workflow|
          next unless entry_matches_event?(self.class.entry_node(workflow))

          Automation::WorkflowRunner.start(workflow, @lead, event: @event, automation_event: @automation_event)
        end
        resume_waiting_executions
      end
    end

    private

    def entry_matches_event?(entry)
      config = entry.fetch(:config, {}).with_indifferent_access
      return false unless whatsapp_campaign_matches?(config)
      return false unless distribution_rule_matches?(config)
      return true if @lead.nil? && campaign_recipient_event?

      case @event
      when "lead_created"
        lead_matches?(config, fields: %i[stage source])
      when "lead_stage_changed"
        stage_change_matches?(config)
      when "whatsapp_received"
        lead_matches?(config, fields: %i[stage]) && whatsapp_message_matches?(config)
      when "proposal_viewed", "proposal_accepted", "proposal_rejected"
        lead_matches?(config, fields: %i[stage])
      when *interest_events
        lead_matches?(config, fields: %i[stage source]) && interest_score_matches?(config)
      when "scheduled_routine"
        lead_matches?(config, fields: %i[stage source])
      else
        true
      end
    end

    def resume_waiting_executions
      return unless @automation_event

      scope = AutomationExecution.where(lead_id: @lead&.id, status: "waiting")
      scope = scope.where(tenant: Current.tenant) if Current.tenant

      scope
        .includes(:automation_workflow, :automation_workflow_version)
        .find_each do |execution|
          next unless execution.automation_workflow&.active?

          step = execution.steps.where(status: "waiting", node_type: %w[await_event await_whatsapp_response response_router]).order(:id).last
          next unless step

          node = waiting_node_for(execution, step.node_id, step.node_type)
          next unless node

          if step.node_type.to_s == "response_router"
            resume_response_router(execution, step, node)
            next
          end

          if step.node_type.to_s == "await_whatsapp_response"
            resume_await_whatsapp_response(execution, step, node)
            next
          end

          next unless await_event_matches?(node)

          output = step.output.to_h.with_indifferent_access
          next_ids = Array(output[:resume_node_ids].presence || output[:resume_node_id]).reject(&:blank?)
          step.update!(
            status: "completed",
            finished_at: Time.current,
            output: step.output.to_h.merge(
              "matched_event_id" => @automation_event.id,
              "matched_event" => @event
            )
          )
          execution.update!(status: "pending", current_node_id: nil)
          if next_ids.any?
            next_ids.each { |next_id| Automation::RunWorkflowJob.perform_later(execution.id, next_id) }
          else
            Automation::RunWorkflowJob.perform_later(execution.id)
          end
        end
    end

    def waiting_node_for(execution, node_id, node_type)
      definition = execution.automation_workflow_version&.definition_hash || {}
      Array(definition[:nodes])
        .map { |node| node.is_a?(Hash) ? node.with_indifferent_access : {} }
        .find { |node| node[:id].to_s == node_id.to_s && node[:type].to_s == node_type.to_s }
    end

    def await_event_matches?(node)
      config = node.fetch(:config, {}).with_indifferent_access
      return false unless config[:trigger].to_s == @event

      case @event
      when "lead_stage_changed"
        stage_change_matches?(config)
      when "whatsapp_received"
        lead_matches?(config, fields: %i[stage]) && whatsapp_message_matches?(config)
      when "proposal_viewed", "proposal_accepted", "proposal_rejected", "lead_created", "scheduled_routine", *interest_events
        lead_matches?(config, fields: %i[stage source])
      else
        true
      end
    end

    def await_whatsapp_response_matches?(node)
      return false unless @event == "whatsapp_received"

      config = node.fetch(:config, {}).with_indifferent_access
      lead_matches?(config, fields: %i[stage]) && whatsapp_message_matches?(config)
    end

    def stage_change_matches?(config)
      from = config[:from_stage].to_s
      to = config[:to_stage].to_s
      payload = (@automation_event&.payload || {}).with_indifferent_access

      from_matches = from.blank? || Lead.status_value(payload[:from]) == Lead.status_value(from)
      to_matches = to.blank? || Lead.status_value(payload[:to]) == Lead.status_value(to)

      from_matches && to_matches
    end

    def lead_matches?(config, fields:)
      return false unless distribution_rule_matches?(config)

      fields.all? do |field|
        expected = config[field].to_s
        next true if expected.blank?
        next false unless @lead

        case field
        when :stage
          Lead.status_value(@lead.status) == Lead.status_value(expected)
        when :source
          @lead.origin.to_s.casecmp?(expected)
        else
          true
        end
      end
    end

    def distribution_rule_matches?(config)
      distribution_rule_ids = self.class.distribution_rule_ids_for(config)
      return true if distribution_rule_ids.empty?
      return false unless @lead

      distribution_rule_ids.include?(@lead.distribution_rule_id)
    end

    def self.distribution_rule_ids_for(config)
      config_hash = config.respond_to?(:with_indifferent_access) ? config.with_indifferent_access : {}
      Array(config_hash[:distribution_rule_ids]).filter_map do |id|
        integer_id = id.to_i
        integer_id.positive? ? integer_id : nil
      end
    end

    def whatsapp_message_matches?(config)
      contains = config[:message_contains].to_s.strip
      not_contains = config[:message_not_contains].to_s.strip
      return true if contains.blank? && not_contains.blank?

      body = whatsapp_message_body
      contains_match = contains.blank? || body.downcase.include?(contains.downcase)
      not_contains_match = not_contains.blank? || !body.downcase.include?(not_contains.downcase)

      contains_match && not_contains_match
    end

    def whatsapp_message_body
      payload = (@automation_event&.payload || {}).with_indifferent_access
      return "" unless @automation_event&.tenant && payload[:whatsapp_message_id].present?

      @automation_event.tenant.whatsapp_messages.find_by(id: payload[:whatsapp_message_id])&.body.to_s
    end

    def resume_response_router(execution, step, node)
      return unless @event == "whatsapp_received"

      config = node.fetch(:config, {}).with_indifferent_access
      return unless lead_matches?(config, fields: %i[stage])

      route = matching_response_route(config)
      return unless route

      route_id = route[:id].presence || "route_#{Array(config[:routes]).index(route)}"
      context = execution.context.to_h.deep_dup
      context["response_router_matches"] ||= {}
      context["response_router_matches"][node[:id].to_s] = {
        "route_id" => route_id,
        "route_label" => route[:name].presence || route[:label].presence || "Fluxo de resposta",
        "automation_event_id" => @automation_event.id,
        "actions" => response_route_actions(route)
      }

      step.update!(
        status: "completed",
        finished_at: Time.current,
        output: step.output.to_h.merge(
          "matched_event_id" => @automation_event.id,
          "matched_event" => @event,
          "matched_route_id" => route_id,
          "matched_route_label" => route[:name].presence || route[:label]
        )
      )
      execution.update!(status: "pending", current_node_id: nil, context: context)
      Automation::RunWorkflowJob.perform_later(execution.id, node[:id])
    end

    def resume_await_whatsapp_response(execution, step, node)
      return unless await_whatsapp_response_matches?(node)

      output = step.output.to_h.with_indifferent_access
      next_ids = Array(output[:resume_node_ids].presence || output[:resume_node_id]).reject(&:blank?)
      next_ids = whatsapp_response_resume_node_ids(execution, node, next_ids)
      context = execution.context.to_h.deep_dup
      context["whatsapp_response"] = whatsapp_response_context_for(node)

      step.update!(
        status: "completed",
        finished_at: Time.current,
        output: step.output.to_h.merge(
          "matched_event_id" => @automation_event.id,
          "matched_event" => @event,
          "response_context" => true
        )
      )
      execution.update!(status: "pending", current_node_id: nil, context: context)

      if next_ids.any?
        next_ids.each { |next_id| Automation::RunWorkflowJob.perform_later(execution.id, next_id) }
      else
        Automation::RunWorkflowJob.perform_later(execution.id)
      end
    end

    def whatsapp_response_resume_node_ids(execution, await_node, next_ids)
      return next_ids if next_ids.blank?

      definition = execution.automation_workflow_version&.definition_hash || {}
      nodes = Array(definition[:nodes]).map { |item| item.is_a?(Hash) ? item.with_indifferent_access : {} }
      by_id = nodes.index_by { |item| item[:id].to_s }
      candidates = next_ids.filter_map { |id| by_id[id.to_s] }

      matched_conditions = candidates
        .select { |item| item[:type].to_s == "response_condition" }
        .select { |item| response_condition_config_matches?(item.fetch(:config, {})) }
        .filter_map { |item| item[:id] }

      return matched_conditions if matched_conditions.any?

      no_match_fallbacks = candidates
        .select { |item| item[:type].to_s == "response_fallback" && (item[:config] || {})[:fallback_type].to_s != "timeout" }
        .filter_map { |item| item[:id] }

      no_match_fallbacks.presence || next_ids
    end

    def response_condition_config_matches?(config)
      condition = (config || {}).with_indifferent_access
      response_condition_matches?(condition)
    end

    def whatsapp_response_context_for(node)
      payload = (@automation_event&.payload || {}).with_indifferent_access
      {
        "source_node_id" => node[:id],
        "event_id" => @automation_event.id,
        "event" => @event,
        "payload" => payload.to_h,
        "body" => whatsapp_message_body,
        "lead_status" => @lead.status,
        "received_at" => Time.current.iso8601
      }
    end

    def matching_response_route(config)
      Array(config[:routes]).map { |route| route.is_a?(Hash) ? route.with_indifferent_access : {} }.find do |route|
        conditions = Array(route[:conditions]).map { |condition| condition.is_a?(Hash) ? condition.with_indifferent_access : {} }
        next false if conditions.empty?

        conditions.all? { |condition| response_condition_matches?(condition) }
      end
    end

    def response_condition_matches?(condition)
      return button_payload_or_text_condition_matches?(condition) if condition[:match_strategy].to_s == "button_payload_or_text"

      value = response_route_value(condition[:field])
      expected = condition[:value].to_s.strip

      case condition[:operator].to_s
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

    def button_payload_or_text_condition_matches?(condition)
      expected_payload = condition[:button_payload].presence || condition[:button_key].presence || condition[:value].presence
      expected_text = condition[:button_text].presence || condition[:fallback_value].presence
      payload_value = response_route_value("interaction.button_payload")
      text_value = response_route_value("interaction.button_text")

      (expected_payload.present? && payload_value.to_s.casecmp?(expected_payload.to_s)) ||
        (expected_text.present? && text_value.to_s.casecmp?(expected_text.to_s))
    end

    def response_route_value(field)
      payload = (@automation_event&.payload || {}).with_indifferent_access
      case field.to_s
      when "message.body"
        whatsapp_message_body
      when "interaction.button_text"
        payload.dig(:button, :title).presence ||
          payload.dig(:interactive, :button_reply, :title).presence ||
          payload[:button_text].presence ||
          whatsapp_message_body
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

    def whatsapp_campaign_matches?(config)
      campaign_id = config[:whatsapp_campaign_id].to_i
      return true unless campaign_id.positive?

      payload = (@automation_event&.payload_hash || {}).with_indifferent_access
      payload[:whatsapp_campaign_id].to_i == campaign_id
    end

    def response_route_actions(route)
      Array(route[:actions]).map { |action| action.is_a?(Hash) ? action.with_indifferent_access : {} }.filter_map do |action|
        type = action[:type].presence || action[:action_type].presence
        next if type.blank?

        action.merge("type" => type).except("action_type").compact
      end
    end

    def interest_score_matches?(config)
      minimum = config[:minimum_score].to_i
      return true if minimum <= 0

      payload = (@automation_event&.payload || {}).with_indifferent_access
      scores = Array(payload[:matches]).filter_map { |match| match.with_indifferent_access[:score].to_i }
      scores.any? { |score| score >= minimum }
    end

    def interest_events
      %w[
        interest_profile_detected
        matching_property_found
        lead_without_matching_property
        interest_profile_incomplete
        interested_property_price_dropped
        lead_repeated_similar_property_views
      ]
    end

    def campaign_recipient_event?
      (@automation_event&.payload_hash || {}).with_indifferent_access[:whatsapp_campaign_recipient_id].present?
    end
  end
end
