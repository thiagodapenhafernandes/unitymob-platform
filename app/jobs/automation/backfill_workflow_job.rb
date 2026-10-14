module Automation
  class BackfillWorkflowJob < ApplicationJob
    queue_as :default
    SNAPSHOT_TRIGGERS = %w[lead_created lead_idle scheduled_routine].freeze

    def perform(workflow_id, version_id)
      workflow = AutomationWorkflow.find_by(id: workflow_id)
      return unless workflow&.active? && workflow.active_version_id == version_id
      version = workflow.active_version
      config = Automation::WorkflowDispatcher.entry_node(workflow).fetch(:config, {}).with_indifferent_access
      return unless config[:entry_policy] == "existing_and_future"

      Current.set(tenant: workflow.tenant) do
        trigger = config[:trigger].to_s
        @bucket = Automation::ScheduleCalculator.recurring_bucket(config, now: version.published_at) if trigger == "scheduled_routine"
        if SNAPSHOT_TRIGGERS.include?(trigger)
          Automation::LeadCandidates.for(workflow.tenant, config, trigger: trigger)
            .where("leads.created_at <= ?", version.published_at).find_each do |lead|
              emit(workflow, version, config, lead, {})
            end
        else
          # Um evento real mais recente por lead; não inventa respostas nem transições.
          events = workflow.tenant.automation_events.where(name: trigger).where.not(lead_id: nil)
            .where.not(source: "automation_backfill").where("occurred_at <= ?", version.published_at)
            .select("DISTINCT ON (lead_id) automation_events.*").order(:lead_id, occurred_at: :desc, id: :desc)
          if trigger == "whatsapp_flow_button"
            events = events.where(id: workflow.executions.where.not(automation_event_id: nil).select(:automation_event_id))
          end
          if config[:whatsapp_campaign_id].present?
            events = events.where("payload ->> 'whatsapp_campaign_id' = ?", config[:whatsapp_campaign_id].to_s)
          end
          cursor = 0
          loop do
            batch = events.where("lead_id > ?", cursor).includes(:lead).limit(200).to_a
            break if batch.empty?
            batch.each { |event| emit(workflow, version, config, event.lead, event.payload_hash) if event.lead }
            cursor = batch.last.lead_id
          end
        end
      end
    end

    private

    def emit(workflow, version, config, lead, payload)
      return unless workflow.reload.active? && workflow.active_version_id == version.id
      trigger = config[:trigger].to_s
      bucket = @bucket
      key = case trigger
            when "lead_idle" then "lead_idle:workflow:#{workflow.id}:lead:#{lead.id}"
            when "scheduled_routine" then "scheduled_routine:workflow:#{workflow.id}:lead:#{lead.id}:bucket:#{bucket}"
            else "backfill:workflow:#{workflow.id}:version:#{version.id}:lead:#{lead.id}"
            end
      Automation::EventBus.emit(trigger, lead: lead, source: "automation_backfill",
        payload: payload.merge(workflow_id: workflow.id, workflow_version_id: version.id, bucket: bucket), idempotency_key: key)
    end
  end
end
