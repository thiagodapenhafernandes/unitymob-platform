class AddPropertyLeadMessagesToContactSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :contact_settings, :sale_lead_success_message, :text
    add_column :contact_settings, :rent_lead_success_message, :text
    add_column :contact_settings, :sale_rent_lead_success_message, :text
    add_column :contact_settings, :sale_whatsapp_message, :text
    add_column :contact_settings, :rent_whatsapp_message, :text
    add_column :contact_settings, :sale_rent_whatsapp_message, :text
  end
end
