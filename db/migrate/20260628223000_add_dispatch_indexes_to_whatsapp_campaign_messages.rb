class AddDispatchIndexesToWhatsappCampaignMessages < ActiveRecord::Migration[7.1]
  def change
    add_index :whatsapp_campaign_messages,
              [:whatsapp_campaign_id, :status, :created_at],
              name: "idx_wa_campaign_messages_dispatch_scan"
  end
end
