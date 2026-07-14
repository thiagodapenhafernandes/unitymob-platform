class CreateAiPropertyShareCollections < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_property_share_collections do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.string :token, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :ai_property_share_collections, :token, unique: true

    create_table :ai_property_share_items do |t|
      t.references :ai_property_share_collection, null: false, foreign_key: true, index: { name: "idx_ai_share_items_collection" }
      t.references :habitation, null: false, foreign_key: true
      t.timestamps
    end
    add_index :ai_property_share_items, [:ai_property_share_collection_id, :habitation_id], unique: true, name: "idx_ai_share_items_unique"

    create_table :ai_property_share_audit_events do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :ai_property_share_collection, null: false, foreign_key: true, index: { name: "idx_ai_share_audits_collection" }
      t.references :admin_user, foreign_key: true
      t.references :lead, foreign_key: true
      t.references :habitation, foreign_key: true
      t.string :event_type, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :ai_property_share_audit_events, [:admin_user_id, :created_at], name: "idx_ai_share_audits_broker_time"
  end
end
