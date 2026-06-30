class ScopeWhatsappCampaignMessageExternalIdToTenant < ActiveRecord::Migration[7.1]
  def up
    remove_index :whatsapp_campaign_messages,
                 name: "index_whatsapp_campaign_messages_on_external_message_id",
                 if_exists: true

    add_index :whatsapp_campaign_messages,
              [:tenant_id, :external_message_id],
              unique: true,
              where: "external_message_id IS NOT NULL",
              name: "index_wa_campaign_messages_on_tenant_and_external_id"
  end

  def down
    remove_index :whatsapp_campaign_messages,
                 name: "index_wa_campaign_messages_on_tenant_and_external_id",
                 if_exists: true

    add_index :whatsapp_campaign_messages,
              :external_message_id,
              unique: true,
              where: "external_message_id IS NOT NULL",
              name: "index_whatsapp_campaign_messages_on_external_message_id"
  end
end
