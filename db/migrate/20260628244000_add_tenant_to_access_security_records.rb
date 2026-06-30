class AddTenantToAccessSecurityRecords < ActiveRecord::Migration[7.1]
  def up
    add_reference :access_control_rules, :tenant, foreign_key: true, index: true
    add_reference :trusted_devices, :tenant, foreign_key: true, index: true

    execute <<~SQL.squish
      UPDATE access_control_rules
      SET tenant_id = admin_users.tenant_id
      FROM admin_users
      WHERE access_control_rules.tenant_id IS NULL
        AND access_control_rules.created_by_id = admin_users.id
    SQL

    execute <<~SQL.squish
      UPDATE access_control_rules
      SET tenant_id = admin_users.tenant_id
      FROM admin_users
      WHERE access_control_rules.tenant_id IS NULL
        AND access_control_rules.admin_user_id = admin_users.id
    SQL

    execute <<~SQL.squish
      UPDATE access_control_rules
      SET tenant_id = profiles.tenant_id
      FROM profiles
      WHERE access_control_rules.tenant_id IS NULL
        AND access_control_rules.profile_id = profiles.id
    SQL

    execute <<~SQL.squish
      UPDATE access_control_rules
      SET tenant_id = tenants.id
      FROM tenants
      WHERE access_control_rules.tenant_id IS NULL
        AND tenants.slug = 'default'
    SQL

    execute <<~SQL.squish
      UPDATE trusted_devices
      SET tenant_id = admin_users.tenant_id
      FROM admin_users
      WHERE trusted_devices.tenant_id IS NULL
        AND trusted_devices.admin_user_id = admin_users.id
    SQL

    execute <<~SQL.squish
      UPDATE trusted_devices
      SET tenant_id = admin_users.tenant_id
      FROM admin_users
      WHERE trusted_devices.tenant_id IS NULL
        AND trusted_devices.created_by_id = admin_users.id
    SQL

    execute <<~SQL.squish
      UPDATE trusted_devices
      SET tenant_id = tenants.id
      FROM tenants
      WHERE trusted_devices.tenant_id IS NULL
        AND tenants.slug = 'default'
    SQL

    change_column_null :access_control_rules, :tenant_id, false
    change_column_null :trusted_devices, :tenant_id, false

    add_index :access_control_rules, [:tenant_id, :rule_type, :scope_type, :enabled], name: "index_access_rules_on_tenant_type_scope_enabled"
    add_index :trusted_devices, [:tenant_id, :admin_user_id, :fingerprint], unique: true, name: "index_trusted_devices_on_tenant_user_fingerprint"
  end

  def down
    remove_index :trusted_devices, name: "index_trusted_devices_on_tenant_user_fingerprint"
    remove_index :access_control_rules, name: "index_access_rules_on_tenant_type_scope_enabled"
    remove_reference :trusted_devices, :tenant, foreign_key: true, index: true
    remove_reference :access_control_rules, :tenant, foreign_key: true, index: true
  end
end
