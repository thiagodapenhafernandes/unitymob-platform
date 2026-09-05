class AddAttendanceMeasurement < ActiveRecord::Migration[7.1]
  def change
    create_table :staff_sessions do |t|
      t.references :staff, null: false, foreign_key: true
      t.string :role, null: false
      t.datetime :started_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :last_seen_at
      t.datetime :last_activity_at
      t.datetime :ended_at
      t.string :end_reason
      t.timestamps
    end
    add_index :staff_sessions, [:ended_at, :expires_at]
    create_table :staff_presence_windows do |t|
      t.references :staff_session, null: false, foreign_key: true
      t.datetime :started_at, null: false
      t.datetime :confirmed_until, null: false
    end
    create_table :support_ticket_events do |t|
      t.references :ticket, null: false, foreign_key: { to_table: :support_tickets }
      t.references :staff, foreign_key: true
      t.string :kind, null: false
      t.string :status, null: false
      t.bigint :assignee_id
      t.jsonb :details, null: false, default: {}
      t.datetime :occurred_at, null: false
    end
    add_foreign_key :support_ticket_events, :staffs, column: :assignee_id
    add_index :support_ticket_events, [:ticket_id, :occurred_at, :id]
    add_index :support_ticket_events, [:staff_id, :occurred_at]
    create_table :sla_policies do |t|
      t.string :priority, null: false
      t.integer :first_response_minutes
      t.integer :resolution_minutes
      t.timestamps
    end
    add_index :sla_policies, :priority, unique: true
    create_table :sla_policy_changes do |t|
      t.references :staff, null: false, foreign_key: true
      t.string :priority, null: false
      t.jsonb :changeset, null: false, default: {}
      t.datetime :occurred_at, null: false
    end
  end
end
