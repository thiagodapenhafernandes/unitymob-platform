class CreateOperationalUserActivityLogs < ActiveRecord::Migration[7.1]
  def change
    create_table :operational_user_sessions do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.string :token, null: false
      t.datetime :started_at, null: false
      t.datetime :last_seen_at, null: false
      t.datetime :ended_at
      t.integer :duration_seconds, null: false, default: 0
      t.integer :events_count, null: false, default: 0
      t.string :device_type
      t.string :browser
      t.string :platform
      t.string :ip_digest
      t.string :user_agent_digest
      t.string :entry_path
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :operational_user_sessions, :token, unique: true
    add_index :operational_user_sessions, [:tenant_id, :last_seen_at]
    add_index :operational_user_sessions, [:admin_user_id, :last_seen_at]

    create_table :operational_user_events do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.references :operational_user_session, null: false, foreign_key: true, index: { name: "idx_operational_events_on_session_id" }
      t.references :habitation, foreign_key: true
      t.string :name, null: false
      t.string :path
      t.string :request_method
      t.datetime :occurred_at, null: false
      t.integer :duration_seconds
      t.string :query_text
      t.integer :result_count
      t.jsonb :filter_params, null: false, default: {}
      t.jsonb :visible_habitation_ids, null: false, default: []
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :operational_user_events, [:tenant_id, :occurred_at]
    add_index :operational_user_events, [:admin_user_id, :occurred_at]
    add_index :operational_user_events, [:tenant_id, :name, :occurred_at], name: "idx_operational_events_on_tenant_name_time"
    add_index :operational_user_events, [:habitation_id, :name], name: "idx_operational_events_on_habitation_name"
  end
end
