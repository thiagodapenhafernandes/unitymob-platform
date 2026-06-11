class AddSitePhoneSettingsToWhatsappBusinessIntegrations < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_business_integrations, :default_whatsapp_number, :string
    add_column :whatsapp_business_integrations, :sale_whatsapp_number, :string
    add_column :whatsapp_business_integrations, :rent_whatsapp_number, :string
    add_column :whatsapp_business_integrations, :sale_rent_whatsapp_number, :string
    add_column :whatsapp_business_integrations, :sale_requires_lead_form, :boolean, null: false, default: true
    add_column :whatsapp_business_integrations, :rent_requires_lead_form, :boolean, null: false, default: true
    add_column :whatsapp_business_integrations, :sale_rent_requires_lead_form, :boolean, null: false, default: true
  end
end
