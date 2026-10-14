module Automation
  class RunWorkflowJob < ApplicationJob
    queue_as :default

    def perform(execution_id, node_id = nil, waiting_step_id = nil, cause = "timeout")
      execution = AutomationExecution.includes(:automation_workflow, :automation_workflow_version, :lead).find_by(id: execution_id)
      return unless execution&.lead

      execution.with_lock do
        return unless execution.automation_workflow.reload.active?
        return unless tenant_consistent?(execution)
        return if %w[completed failed canceled].include?(execution.status)
        return if waiting_step_id.blank? && node_id.blank? && execution.status == "waiting"
        if waiting_step_id.blank? && node_id.present? && execution.status == "waiting"
          # Compatibilidade com continuações enfileiradas antes do identificador de espera.
          legacy_step = execution.steps.where(status: "waiting").order(id: :desc).find do |candidate|
            ids = candidate.output["resume_jobs"] || candidate.output["resume_node_ids"] || Array(candidate.output["retry_node_id"] || candidate.output["resume_node_id"])
            Array(ids).map(&:to_s).include?(node_id.to_s)
          end
          return unless legacy_step
          legacy_step.update!(output: legacy_step.output.merge("resume_jobs" => legacy_step.output["resume_node_ids"] || [node_id], "resume_cause" => "timeout")) unless legacy_step.output.key?("resume_cause")
          waiting_step_id = legacy_step.id
        end

        if waiting_step_id
          step = execution.steps.find_by(id: waiting_step_id)
          return unless step && step.output["resume_cause"].to_s == cause.to_s
          key = node_id.to_s.presence || "__finish__"
          completed = Array(step.output["resumed_nodes"])
          return if completed.include?(key)
          step.update!(status: "completed", finished_at: Time.current,
                       output: step.output.merge("resumed_nodes" => completed + [key]))
          if node_id.blank?
            execution.update!(status: "completed", current_node_id: nil, finished_at: Time.current)
            return
          end
        end

        Current.set(tenant: execution.tenant) do
          Automation::WorkflowRunner.run(execution, from_node_id: node_id)
          if execution.status == "completed"
            waiting = execution.steps.where(status: "waiting").order(:id).last
            if waiting
              execution.update!(status: "waiting", current_node_id: waiting.node_id, finished_at: nil)
            elsif step && (Array(step.output["resume_jobs"]) - Array(step.output["resumed_nodes"])).any?
              execution.update!(status: "pending", finished_at: nil)
            end
          end
        end
      end
    end

    private

    def tenant_consistent?(execution)
      tenant_id = execution.tenant_id
      tenant_id.present? &&
        execution.automation_workflow&.tenant_id == tenant_id &&
        execution.automation_workflow_version&.tenant_id == tenant_id &&
        execution.lead&.tenant_id == tenant_id
    end
  end
end
