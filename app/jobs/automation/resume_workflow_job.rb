module Automation
  class ResumeWorkflowJob < ApplicationJob
    queue_as :default

    def perform(workflow_id)
      workflow = AutomationWorkflow.find_by(id: workflow_id)
      return unless workflow&.active?
      Current.set(tenant: workflow.tenant) do
        workflow.executions.where(status: %w[pending waiting]).find_each do |execution|
          execution.with_lock do
            next unless workflow.reload.active?
            queued = false
            execution.steps.where(status: %w[waiting completed]).find_each do |step|
              ids = step.output["resume_jobs"] || step.output["resume_node_ids"] || Array(step.output["retry_node_id"] || step.output["resume_node_id"])
              next unless step.status == "waiting" || (Array(ids) - Array(step.output["resumed_nodes"])).any?
              next unless step.scheduled_for || step.output.key?("resume_jobs")

              run_at = step.status == "waiting" ? [step.scheduled_for || Time.current, Time.current].max : Time.current
              step.enqueue_resume!(node_ids: ids, scheduled_for: run_at,
                                   cause: step.output["resume_cause"] || "timeout")
              queued = true
            end
            Automation::RunWorkflowJob.perform_later(execution.id, execution.current_node_id) if !queued && execution.status == "pending"
          end
        end
        workflow.tenant.automation_events.pending.where(source: %w[automation_tick automation_backfill])
          .where("payload ->> 'workflow_id' = ?", workflow.id.to_s).find_each do |event|
            Automation::ProcessEventJob.perform_later(event.id)
          end
        workflow.active_version.enqueue_existing_leads!
      end
    end
  end
end
