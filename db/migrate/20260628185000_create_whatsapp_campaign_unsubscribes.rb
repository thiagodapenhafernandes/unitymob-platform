class CreateWhatsappCampaignUnsubscribes < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_campaign_unsubscribes do |t|
      t.references :whatsapp_sender_number, null: false, foreign_key: true, index: { name: "idx_wa_unsub_sender" }
      t.references :whatsapp_campaign, foreign_key: true, index: { name: "idx_wa_unsub_campaign" }
      t.references :whatsapp_campaign_message, foreign_key: true, index: { name: "idx_wa_unsub_campaign_message" }
      t.references :whatsapp_campaign_recipient, foreign_key: true, index: { name: "idx_wa_unsub_campaign_recipient" }
      t.references :unsubscribed_by_message, foreign_key: { to_table: :whatsapp_messages }, index: { name: "idx_wa_unsub_inbound_message" }
      t.references :reenabled_by, foreign_key: { to_table: :admin_users }, index: { name: "idx_wa_unsub_reenabled_by" }
      t.string :phone_number, null: false
      t.string :contact_name
      t.string :source, null: false, default: "campaign_button"
      t.string :reason, null: false, default: "Descadastro solicitado pelo contato."
      t.datetime :unsubscribed_at, null: false
      t.datetime :reenabled_at
      t.text :reenable_reason
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :whatsapp_campaign_unsubscribes,
              [:whatsapp_sender_number_id, :phone_number],
              unique: true,
              where: "reenabled_at IS NULL",
              name: "idx_wa_unsub_active_sender_phone"
    add_index :whatsapp_campaign_unsubscribes, :phone_number, name: "idx_wa_unsub_phone"
    add_index :whatsapp_campaign_unsubscribes, :unsubscribed_at, name: "idx_wa_unsub_unsubscribed_at"

    reversible do |dir|
      dir.up { backfill_existing_campaign_unsubscribes }
    end
  end

  private

  def backfill_existing_campaign_unsubscribes
    execute <<~SQL.squish
      INSERT INTO whatsapp_campaign_unsubscribes (
        whatsapp_sender_number_id,
        whatsapp_campaign_id,
        whatsapp_campaign_message_id,
        whatsapp_campaign_recipient_id,
        phone_number,
        contact_name,
        source,
        reason,
        unsubscribed_at,
        metadata,
        created_at,
        updated_at
      )
      SELECT DISTINCT ON (campaigns.whatsapp_sender_number_id, recipients.phone_number)
        campaigns.whatsapp_sender_number_id,
        campaigns.id,
        messages.id,
        recipients.id,
        recipients.phone_number,
        recipients.name,
        'campaign_button',
        'Descadastro solicitado pelo contato.',
        COALESCE(recipients.unsubscribed_at, recipients.updated_at, NOW()),
        jsonb_build_object('backfilled', true),
        NOW(),
        NOW()
      FROM whatsapp_campaign_recipients recipients
      INNER JOIN whatsapp_campaigns campaigns ON campaigns.id = recipients.whatsapp_campaign_id
      LEFT JOIN whatsapp_campaign_messages messages ON messages.whatsapp_campaign_recipient_id = recipients.id
      WHERE recipients.conversion_status = 'unsubscribed'
        AND campaigns.whatsapp_sender_number_id IS NOT NULL
        AND recipients.phone_number IS NOT NULL
        AND recipients.phone_number <> ''
      ORDER BY campaigns.whatsapp_sender_number_id, recipients.phone_number, recipients.unsubscribed_at DESC NULLS LAST, recipients.updated_at DESC
      ON CONFLICT DO NOTHING
    SQL
  end
end
