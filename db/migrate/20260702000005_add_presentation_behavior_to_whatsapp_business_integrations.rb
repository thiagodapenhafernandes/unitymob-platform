class AddPresentationBehaviorToWhatsappBusinessIntegrations < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_business_integrations, :presentation_enabled, :boolean, null: false, default: true
    add_column :whatsapp_business_integrations, :require_presentation, :boolean, null: false, default: false
  end
end
