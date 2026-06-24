class CreateInterestIntelligenceFoundation < ActiveRecord::Migration[7.1]
  def change
    create_table :public_navigation_sessions do |t|
      t.string :token, null: false
      t.references :lead, foreign_key: true
      t.string :user_agent_digest
      t.string :landing_url
      t.string :referrer_url
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :public_navigation_sessions, :token, unique: true
    add_index :public_navigation_sessions, :last_seen_at

    create_table :public_navigation_events do |t|
      t.references :public_navigation_session, null: false, foreign_key: true
      t.references :lead, foreign_key: true
      t.references :habitation, foreign_key: true
      t.string :name, null: false
      t.string :path
      t.integer :duration_seconds
      t.datetime :occurred_at, null: false
      t.jsonb :search_params, null: false, default: {}
      t.jsonb :property_snapshot, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :public_navigation_events, [:public_navigation_session_id, :occurred_at], name: "idx_public_nav_events_session_time"
    add_index :public_navigation_events, [:lead_id, :name], name: "idx_public_nav_events_lead_name"
    add_index :public_navigation_events, [:habitation_id, :name], name: "idx_public_nav_events_habitation_name"

    add_reference :client_property_interests, :lead, foreign_key: true unless column_exists?(:client_property_interests, :lead_id)

    change_table :layout_settings do |t|
      t.boolean :interest_intelligence_enabled, null: false, default: true
      t.text :interest_intelligence_instructions
      t.jsonb :interest_intelligence_settings, null: false, default: {}
    end
  end
end
