class AddResponseDecisionsToWhatsappCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_campaigns, :response_decisions, :jsonb, null: false, default: {}

    add_column :whatsapp_campaign_messages, :reply_type, :string
    add_column :whatsapp_campaign_messages, :reply_body, :text
    add_column :whatsapp_campaign_messages, :reply_button_text, :string
    add_column :whatsapp_campaign_messages, :reply_button_payload, :string
    add_column :whatsapp_campaign_messages, :reply_payload, :jsonb, null: false, default: {}

    add_index :whatsapp_campaign_messages, :reply_button_text
    add_index :whatsapp_campaign_messages, :reply_type
  end
end
