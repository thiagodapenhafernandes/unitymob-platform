class AddWebhookFieldsToWhatsappBusinessIntegrations < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_business_integrations, :webhook_verify_token, :string
    add_column :whatsapp_business_integrations, :app_secret, :string
  end
end
