class CreateTenantProfileGovernance < ActiveRecord::Migration[7.1]
  DEFAULT_TENANT_NAME = "Conta principal"

  def up
    create_table :tenants do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :tenants, :slug, unique: true

    default_tenant_id = insert_default_tenant

    add_reference :profiles, :tenant, foreign_key: true
    add_column :profiles, :axis, :string, null: false, default: "vertical"
    add_reference :profiles, :vertical_profile, foreign_key: { to_table: :profiles }
    add_column :profiles, :position, :integer
    add_column :profiles, :locked, :boolean, null: false, default: false

    add_reference :admin_users, :tenant, foreign_key: true
    add_reference :admin_users, :horizontal_profile, foreign_key: { to_table: :profiles }

    execute("UPDATE profiles SET tenant_id = #{default_tenant_id}, axis = 'vertical' WHERE tenant_id IS NULL")
    execute("UPDATE admin_users SET tenant_id = #{default_tenant_id} WHERE tenant_id IS NULL")

    normalize_existing_profile_positions
    ensure_builtin_profiles(default_tenant_id)

    change_column_null :profiles, :tenant_id, false
    change_column_null :admin_users, :tenant_id, false

    add_index :profiles, [:tenant_id, :axis, :position]
    add_index :profiles, [:tenant_id, :key], unique: true, where: "key IS NOT NULL"
    add_index :profiles, [:tenant_id, :vertical_profile_id, :name], unique: true, where: "axis = 'horizontal'"
    add_index :admin_users, [:tenant_id, :profile_id]
    add_index :admin_users, [:tenant_id, :manager_id]
  end

  def down
    remove_index :admin_users, [:tenant_id, :manager_id]
    remove_index :admin_users, [:tenant_id, :profile_id]
    remove_reference :admin_users, :horizontal_profile, foreign_key: { to_table: :profiles }
    remove_reference :admin_users, :tenant, foreign_key: true

    remove_index :profiles, [:tenant_id, :vertical_profile_id, :name]
    remove_index :profiles, [:tenant_id, :key]
    remove_index :profiles, [:tenant_id, :axis, :position]
    remove_column :profiles, :locked
    remove_column :profiles, :position
    remove_reference :profiles, :vertical_profile, foreign_key: { to_table: :profiles }
    remove_column :profiles, :axis
    remove_reference :profiles, :tenant, foreign_key: true

    drop_table :tenants
  end

  private

  def insert_default_tenant
    insert(<<~SQL.squish)
      INSERT INTO tenants (name, slug, active, created_at, updated_at)
      VALUES ('#{DEFAULT_TENANT_NAME}', 'default', TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      RETURNING id
    SQL
  end

  def insert(sql)
    select_value(sql).to_i
  end

  def normalize_existing_profile_positions
    rows = select_all("SELECT id, key, name FROM profiles ORDER BY name ASC").to_a
    rows.each_with_index do |row, index|
      key = row["key"].presence
      position =
        if key == "administrador"
          0
        elsif key == "corretor"
          10_000
        else
          (index + 1) * 100
        end

      execute("UPDATE profiles SET position = #{position} WHERE id = #{row["id"].to_i}")
    end
  end

  def ensure_builtin_profiles(default_tenant_id)
    owner_exists = select_value("SELECT 1 FROM profiles WHERE tenant_id = #{default_tenant_id} AND key IN ('tenant_owner', 'administrador') LIMIT 1")
    unless owner_exists
      execute(<<~SQL.squish)
        INSERT INTO profiles (name, permissions, active, created_at, updated_at, key, tenant_id, axis, position, locked)
        VALUES ('Tenant Owner', '{"admin": true}'::jsonb, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'tenant_owner', #{default_tenant_id}, 'vertical', 0, TRUE)
      SQL
    end

    agent_exists = select_value("SELECT 1 FROM profiles WHERE tenant_id = #{default_tenant_id} AND key IN ('agent', 'corretor') LIMIT 1")
    unless agent_exists
      execute(<<~SQL.squish)
        INSERT INTO profiles (name, permissions, active, created_at, updated_at, key, tenant_id, axis, position, locked)
        VALUES ('Agent', '{}'::jsonb, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, 'agent', #{default_tenant_id}, 'vertical', 10000, TRUE)
      SQL
    end

    execute("UPDATE profiles SET locked = TRUE, position = 0 WHERE tenant_id = #{default_tenant_id} AND key IN ('tenant_owner', 'administrador')")
    execute("UPDATE profiles SET locked = TRUE, position = 10000 WHERE tenant_id = #{default_tenant_id} AND key IN ('agent', 'corretor')")
  end
end
