class AddSiteRedirectAfterCaptureToWhatsappBusinessIntegrations < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_business_integrations, :sale_redirect_after_capture, :boolean, null: false, default: true
    add_column :whatsapp_business_integrations, :rent_redirect_after_capture, :boolean, null: false, default: true
    add_column :whatsapp_business_integrations, :sale_rent_redirect_after_capture, :boolean, null: false, default: true
  end
end
