class AddAutomationWorkflowToWhatsappCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_reference :whatsapp_campaigns, :automation_workflow, null: true, foreign_key: true
  end
end
