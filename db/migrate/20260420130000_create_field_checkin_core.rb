class CreateFieldCheckinCore < ActiveRecord::Migration[7.1]
  # Habilita PostGIS e cria tabelas fundamentais do módulo de campo (stores + shifts).
  # Usamos PostGIS via SQL direto (coluna geography), mantendo o adapter
  # postgresql padrão do Rails para não impactar o resto do app.
  def up
    enable_extension "postgis" unless extension_enabled?("postgis")

    create_table :stores do |t|
      t.string :name, null: false
      t.string :slug
      t.string :address
      t.string :zip_code
      t.string :city
      t.string :state, limit: 2
      t.string :phone
      t.string :creci
      t.integer :geofence_radius_meters, default: 150, null: false
      t.integer :out_of_radius_tolerance_minutes, default: 10, null: false
      t.integer :auto_checkout_after_minutes, default: 60, null: false
      t.string :timezone, default: "America/Sao_Paulo", null: false
      t.boolean :active, default: true, null: false
      t.references :director_admin_user, foreign_key: { to_table: :admin_users }
      t.references :footer_store, foreign_key: true
      t.timestamps
    end
    add_index :stores, :active
    add_index :stores, :slug, unique: true

    # Coluna PostGIS via SQL direto (Rails não tem mapper nativo pra geography).
    execute <<~SQL.squish
      ALTER TABLE stores
      ADD COLUMN location geography(POINT, 4326)
    SQL
    execute <<~SQL.squish
      CREATE INDEX index_stores_on_location ON stores USING gist (location)
    SQL

    create_table :store_shifts do |t|
      t.references :store, null: false, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.integer :day_of_week, null: false
      t.time :start_time, null: false
      t.time :end_time, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end
    add_index :store_shifts, [:admin_user_id, :day_of_week, :active],
              name: "idx_store_shifts_agent_day_active"
    add_index :store_shifts, [:store_id, :day_of_week]

    add_column :admin_users, :field_agent_enabled, :boolean, default: false, null: false
    add_reference :admin_users, :default_store, foreign_key: { to_table: :stores }
    add_index :admin_users, :field_agent_enabled
  end

  def down
    remove_reference :admin_users, :default_store, foreign_key: { to_table: :stores }
    remove_column :admin_users, :field_agent_enabled

    drop_table :store_shifts
    execute "DROP INDEX IF EXISTS index_stores_on_location"
    drop_table :stores
    # Não desativa postgis (outros usos futuros podem existir).
  end
end
