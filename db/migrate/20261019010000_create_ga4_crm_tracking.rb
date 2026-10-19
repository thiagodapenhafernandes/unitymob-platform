class CreateGa4CrmTracking < ActiveRecord::Migration[7.1]
  def change
    create_table :ga4_conversion_configs do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.string :measurement_id
      t.text :api_secret
      t.datetime :activated_at
      t.timestamps
    end

    create_table :ga4_conversion_events do |t|
      t.references :tenant, null: false, foreign_key: { on_delete: :cascade }
      t.references :lead, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :deduplication_key, null: false
      t.string :event_name, null: false
      t.string :event_id, null: false
      t.string :measurement_id, null: false
      t.text :client_id, null: false
      t.jsonb :parameters, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.string :status, null: false, default: "pending"
      t.string :skip_reason
      t.integer :http_status
      t.datetime :attempted_at
      t.timestamps
    end
    add_index :ga4_conversion_events, [:tenant_id, :deduplication_key], unique: true, name: "idx_ga4_conversion_events_dedup"
    add_index :ga4_conversion_events, [:status, :created_at]
    add_index :ga4_conversion_events, :event_id, unique: true
  end
end
