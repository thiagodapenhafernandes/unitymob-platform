class AddAutomationWorkflowToWhatsappResponseFlows < ActiveRecord::Migration[7.1]
  def change
    add_reference :whatsapp_response_flows, :automation_workflow, null: true, foreign_key: true
  end
end
