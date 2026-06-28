class CreateWhatsappCampaigns < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_campaigns do |t|
      t.references :whatsapp_template, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :admin_users }
      t.string :name, null: false
      t.text :description
      t.string :status, null: false, default: "draft"
      t.jsonb :audience_filters, null: false, default: {}
      t.jsonb :template_variables, null: false, default: {}
      t.datetime :scheduled_at
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :paused_at
      t.datetime :cancelled_at
      t.integer :send_rate, null: false, default: 50
      t.integer :requested_recipients, null: false, default: 0
      t.integer :total_recipients, null: false, default: 0
      t.integer :sent_count, null: false, default: 0
      t.integer :delivered_count, null: false, default: 0
      t.integer :read_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.integer :replied_count, null: false, default: 0
      t.text :failure_reason

      t.timestamps
    end

    add_index :whatsapp_campaigns, :status
    add_index :whatsapp_campaigns, :scheduled_at
    add_index :whatsapp_campaigns, :created_at

    create_table :whatsapp_campaign_messages do |t|
      t.references :whatsapp_campaign, null: false, foreign_key: true
      t.references :lead, null: false, foreign_key: true
      t.references :whatsapp_message, null: true, foreign_key: true
      t.string :phone_number, null: false
      t.string :external_message_id
      t.string :status, null: false, default: "pending"
      t.jsonb :template_variables, null: false, default: {}
      t.datetime :queued_at
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :read_at
      t.datetime :failed_at
      t.datetime :replied_at
      t.text :failure_reason
      t.integer :retry_count, null: false, default: 0
      t.datetime :next_retry_at

      t.timestamps
    end

    add_index :whatsapp_campaign_messages, :external_message_id, unique: true, where: "external_message_id IS NOT NULL"
    add_index :whatsapp_campaign_messages, :status
    add_index :whatsapp_campaign_messages, [:whatsapp_campaign_id, :lead_id], name: "idx_wa_campaign_messages_on_campaign_lead"
    add_index :whatsapp_campaign_messages, :next_retry_at
  end
end
