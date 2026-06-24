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
        entry = entry_node(workflow)
        idle_hours = entry.dig(:config, :idle_hours).to_i
        next unless idle_hours.positive?

        scope = Lead.where("leads.updated_at <= ?", idle_hours.hours.ago)
        stage = entry.dig(:config, :stage)
        scope = scope.where(status: Lead.status_value(stage)) if stage.present?
        source = entry.dig(:config, :source)
        scope = scope.where("origin ILIKE ?", source) if source.present?

        processed = AutomationExecution
          .where(automation_workflow_id: workflow.id)
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

    def self.dispatch_scheduled_routines(limit: 200)
      active_workflows_for_event("scheduled_routine").each do |workflow|
        entry = entry_node(workflow)
        config = entry.fetch(:config, {}).with_indifferent_access
        next unless Automation::ScheduleCalculator.recurring_due?(config)

        bucket = Automation::ScheduleCalculator.recurring_bucket(config)
        scope = Lead.all
        stage = config[:stage]
        scope = scope.where(status: Lead.status_value(stage)) if stage.present?
        source = config[:source]
        scope = scope.where("origin ILIKE ?", source) if source.present?

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

    def self.active_workflows_for_event(event)
      AutomationWorkflow.active.includes(:active_version).select do |workflow|
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
      return unless @lead

      self.class.active_workflows_for_event(@event).each do |workflow|
        next unless entry_matches_event?(self.class.entry_node(workflow))

        Automation::WorkflowRunner.start(workflow, @lead, event: @event, automation_event: @automation_event)
      end
      resume_waiting_executions
    end

    private

    def entry_matches_event?(entry)
      config = entry.fetch(:config, {}).with_indifferent_access

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

      AutomationExecution
        .where(lead_id: @lead.id, status: "waiting")
        .includes(:automation_workflow, :automation_workflow_version)
        .find_each do |execution|
          next unless execution.automation_workflow&.active?

          step = execution.steps.where(status: "waiting", node_type: "await_event").order(:id).last
          next unless step

          node = await_node_for(execution, step.node_id)
          next unless node && await_event_matches?(node)

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

    def await_node_for(execution, node_id)
      definition = execution.automation_workflow_version&.definition_hash || {}
      Array(definition[:nodes])
        .map { |node| node.is_a?(Hash) ? node.with_indifferent_access : {} }
        .find { |node| node[:id].to_s == node_id.to_s && node[:type].to_s == "await_event" }
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

    def stage_change_matches?(config)
      from = config[:from_stage].to_s
      to = config[:to_stage].to_s
      payload = (@automation_event&.payload || {}).with_indifferent_access

      from_matches = from.blank? || Lead.status_value(payload[:from]) == Lead.status_value(from)
      to_matches = to.blank? || Lead.status_value(payload[:to]) == Lead.status_value(to)

      from_matches && to_matches
    end

    def lead_matches?(config, fields:)
      fields.all? do |field|
        expected = config[field].to_s
        next true if expected.blank?

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
      WhatsappMessage.find_by(id: payload[:whatsapp_message_id])&.body.to_s
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
  end
end
