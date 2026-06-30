module Automation
  class RunWorkflowJob < ApplicationJob
    queue_as :default

    def perform(execution_id, node_id = nil)
      execution = AutomationExecution.includes(:automation_workflow, :automation_workflow_version, :lead).find_by(id: execution_id)
      return unless execution&.lead
      return unless execution.automation_workflow.active?
      return unless tenant_consistent?(execution)
      return if %w[completed failed canceled].include?(execution.status)
      return if node_id.present? && execution.current_node_id.blank? && execution.status == "waiting"

      Current.set(tenant: execution.tenant) do
        Automation::WorkflowRunner.run(execution, from_node_id: node_id)
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
