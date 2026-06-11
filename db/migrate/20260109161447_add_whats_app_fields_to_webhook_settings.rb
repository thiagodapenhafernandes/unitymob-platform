class AddWhatsAppFieldsToWebhookSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :webhook_settings, :whatsapp_webhook_url, :string
    add_column :webhook_settings, :lead_capture_enabled, :boolean
  end
end
