class AddAllowPhotoPresentationToWhatsappBusinessIntegrations < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_business_integrations, :allow_photo_presentation, :boolean, null: false, default: false
  end
end
