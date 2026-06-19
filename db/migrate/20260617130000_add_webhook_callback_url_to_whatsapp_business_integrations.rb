class AddWebhookCallbackUrlToWhatsappBusinessIntegrations < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_business_integrations, :webhook_callback_url, :string
  end
end
