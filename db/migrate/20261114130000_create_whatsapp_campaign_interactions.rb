class CreateWhatsappCampaignInteractions < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_campaign_interactions do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :whatsapp_campaign, null: false, foreign_key: {on_delete: :cascade}
      t.references :whatsapp_campaign_message, null: false, foreign_key: {on_delete: :cascade}
      t.references :inbound_whatsapp_message, foreign_key: {to_table: :whatsapp_messages, on_delete: :nullify}
      t.references :source_response, foreign_key: {to_table: :whatsapp_campaign_interactions, on_delete: :cascade}
      t.string :event_key, null: false
      t.string :recipient_key, null: false
      t.string :kind, null: false
      t.string :button_key
      t.string :button_text
      t.text :body
      t.string :action_key
      t.string :action_label
      t.string :outcome
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.timestamps
    end
    add_index :whatsapp_campaign_interactions, [:tenant_id, :event_key], unique: true, name: "index_campaign_interactions_on_tenant_event"
    add_index :whatsapp_campaign_interactions, [:tenant_id, :whatsapp_campaign_id, :occurred_at], name: "index_campaign_interactions_on_campaign_time"
    add_check_constraint :whatsapp_campaign_interactions, "kind IN ('response', 'action')", name: "campaign_interaction_kind"
    add_reference :whatsapp_attendances, :campaign_interaction, foreign_key: {to_table: :whatsapp_campaign_interactions, on_delete: :nullify}
  end
end
