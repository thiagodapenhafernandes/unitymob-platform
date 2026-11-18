class CreateTrackingEventLinks < ActiveRecord::Migration[7.1]
  def change
    create_table :tracking_event_links do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :lead, foreign_key: { on_delete: :nullify }
      t.references :public_form_submission, foreign_key: { on_delete: :nullify }
      t.references :google_stage_conversion_event, foreign_key: { on_delete: :nullify }, index: { name: "idx_tracking_links_google_event" }
      t.references :ga4_conversion_event, foreign_key: { on_delete: :nullify }
      t.string :occurrence_key, null: false
      t.string :occurrence_name, null: false
      t.datetime :occurred_at, null: false
      t.string :transport, null: false
      t.string :external_event_id, null: false
      t.string :destination_key, null: false
      t.string :destination_label, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :attempt_log, null: false, default: []
      t.timestamps
    end
    add_index :tracking_event_links, [:tenant_id, :transport, :external_event_id, :destination_key],
      unique: true, name: "idx_tracking_links_delivery"
    add_index :tracking_event_links, [:tenant_id, :occurrence_key], name: "idx_tracking_links_occurrence"
    add_index :tracking_event_links, [:tenant_id, :lead_id, :occurred_at], name: "idx_tracking_links_lead_journey"
  end
end
