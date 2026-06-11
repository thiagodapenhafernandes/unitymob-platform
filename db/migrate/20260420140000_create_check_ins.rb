class CreateCheckIns < ActiveRecord::Migration[7.1]
  def up
    create_table :check_ins do |t|
      t.references :admin_user, null: false, foreign_key: true
      t.references :store, null: false, foreign_key: true
      t.references :store_shift, foreign_key: true
      t.datetime :checked_in_at, null: false
      t.datetime :checked_out_at
      t.integer :status, default: 0, null: false
      t.integer :checkin_accuracy_meters
      t.integer :checkout_accuracy_meters
      t.inet :checkin_ip
      t.inet :checkout_ip
      t.jsonb :device_info, default: {}
      t.datetime :out_of_radius_since
      t.timestamps
    end

    # Colunas PostGIS via SQL direto (idem Store.location).
    execute "ALTER TABLE check_ins ADD COLUMN checkin_location geography(POINT, 4326)"
    execute "ALTER TABLE check_ins ADD COLUMN checkout_location geography(POINT, 4326)"

    add_index :check_ins, [:admin_user_id, :status]
    add_index :check_ins, [:store_id, :checked_in_at]

    # Garante 1 check-in ativo por corretor (status=0 = active).
    execute <<~SQL.squish
      CREATE UNIQUE INDEX idx_unique_active_checkin_per_user
      ON check_ins (admin_user_id)
      WHERE status = 0
    SQL
  end

  def down
    drop_table :check_ins
  end
end
