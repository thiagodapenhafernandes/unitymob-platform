class CreateAutomationEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :automation_events do |t|
      t.references :lead, null: true, foreign_key: true
      t.string :name, null: false
      t.string :source, null: false, default: "platform"
      t.string :status, null: false, default: "pending"
      t.string :idempotency_key
      t.jsonb :payload, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.datetime :processed_at
      t.text :error_message

      t.timestamps
    end

    add_index :automation_events, :name
    add_index :automation_events, :status
    add_index :automation_events, :idempotency_key, unique: true
    add_index :automation_events,
              [:lead_id, :name, :occurred_at],
              name: "idx_automation_events_lead_name_occurred_at"

    add_reference :automation_runs, :automation_event, null: true, foreign_key: true
    add_reference :automation_executions, :automation_event, null: true, foreign_key: true
  end
end
