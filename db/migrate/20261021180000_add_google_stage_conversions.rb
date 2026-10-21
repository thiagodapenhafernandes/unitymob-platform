class AddGoogleStageConversions < ActiveRecord::Migration[7.1]
  def change
    add_column :lead_pipeline_stages, :google_event, :string, default: "none", null: false
    add_column :leads, :google_business_type, :string
    add_column :webhook_settings, :google_conversions_enabled, :boolean, default: false, null: false
    add_column :webhook_settings, :webhook_secret, :text
    add_index :webhook_settings, :tenant_id, unique: true, where: "google_conversions_enabled = true", name: "index_one_google_webhook_per_tenant"
    add_check_constraint :lead_pipeline_stages, "google_event IN ('none','qualify_lead','visit','proposal','closed')", name: "lead_stages_google_event"
    create_table :google_stage_conversion_events do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :lead, null: false, foreign_key: true
      t.references :webhook_setting, foreign_key: { on_delete: :nullify }
      t.string :conversion_type, null: false
      t.string :status, null: false, default: "pending"
      t.string :skip_reason
      t.text :payload, null: false
      t.text :destination_url, null: false
      t.datetime :occurred_at, null: false
      t.datetime :next_attempt_at
      t.integer :attempt_count, null: false, default: 0
      t.jsonb :attempt_log, null: false, default: []
      t.timestamps
    end
    add_index :google_stage_conversion_events, [:lead_id, :conversion_type], unique: true, name: "index_google_stage_event_identity"
    add_index :google_stage_conversion_events, [:status, :next_attempt_at], name: "index_google_stage_events_pending"
  end
end
