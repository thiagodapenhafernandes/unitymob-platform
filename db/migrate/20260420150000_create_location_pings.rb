class CreateLocationPings < ActiveRecord::Migration[7.1]
  def up
    create_table :location_pings do |t|
      t.references :check_in, null: false, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.integer :accuracy_meters
      t.float :battery_level
      t.boolean :is_mock_location, default: false, null: false
      t.boolean :inside_radius, null: false
      t.inet :ip
      t.string :user_agent
      t.datetime :recorded_at, null: false
      t.boolean :suspicious, default: false, null: false
      t.jsonb :suspicious_reasons, default: []
      t.timestamps
    end

    execute "ALTER TABLE location_pings ADD COLUMN location geography(POINT, 4326) NOT NULL"
    add_index :location_pings, [:check_in_id, :recorded_at]
    add_index :location_pings, [:admin_user_id, :recorded_at]
  end

  def down
    drop_table :location_pings
  end
end
