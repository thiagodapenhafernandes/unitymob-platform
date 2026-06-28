class CreateWhatsappCampaignRecipients < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_campaign_recipients do |t|
      t.references :whatsapp_campaign, null: false, foreign_key: true
      t.references :lead, null: true, foreign_key: true
      t.references :admin_user, null: true, foreign_key: true
      t.string :source, null: false, default: "spreadsheet"
      t.string :name
      t.string :phone_number, null: false
      t.string :email
      t.string :origin
      t.string :status
      t.jsonb :tags, null: false, default: []
      t.jsonb :custom_data, null: false, default: {}
      t.string :conversion_status, null: false, default: "pending"
      t.datetime :converted_at
      t.datetime :unsubscribed_at

      t.timestamps
    end

    add_index :whatsapp_campaign_recipients,
              [:whatsapp_campaign_id, :phone_number],
              unique: true,
              name: "idx_wa_campaign_recipients_on_campaign_phone"
    add_index :whatsapp_campaign_recipients, :source
    add_index :whatsapp_campaign_recipients, :conversion_status
    add_index :whatsapp_campaign_recipients, :tags, using: :gin

    add_reference :whatsapp_campaign_messages,
                  :whatsapp_campaign_recipient,
                  null: true,
                  foreign_key: true,
                  index: { name: "idx_wa_campaign_messages_on_recipient" }
    change_column_null :whatsapp_campaign_messages, :lead_id, true
  end
end
