class AllowSystemAdminsOutsideTenants < ActiveRecord::Migration[7.1]
  def up
    change_column_null :admin_users, :tenant_id, true

    execute <<~SQL.squish
      UPDATE admin_users
      SET tenant_id = NULL,
          profile_id = NULL,
          horizontal_profile_id = NULL,
          manager_id = NULL,
          updated_at = CURRENT_TIMESTAMP
      WHERE super_admin = TRUE
    SQL

    add_check_constraint :admin_users,
                         "super_admin = TRUE OR tenant_id IS NOT NULL",
                         name: "admin_users_tenant_required_unless_system_admin"

    add_check_constraint :admin_users,
                         <<~SQL.squish,
                           super_admin = FALSE
                           OR (
                             tenant_id IS NULL
                             AND profile_id IS NULL
                             AND horizontal_profile_id IS NULL
                             AND manager_id IS NULL
                           )
                         SQL
                         name: "admin_users_system_admin_outside_tenant"
  end

  def down
    remove_check_constraint :admin_users, name: "admin_users_system_admin_outside_tenant"
    remove_check_constraint :admin_users, name: "admin_users_tenant_required_unless_system_admin"

    default_tenant_id = select_value("SELECT id FROM tenants ORDER BY id ASC LIMIT 1")
    if default_tenant_id.present?
      execute <<~SQL.squish
        UPDATE admin_users
        SET tenant_id = #{default_tenant_id.to_i},
            updated_at = CURRENT_TIMESTAMP
        WHERE tenant_id IS NULL
      SQL
    end

    change_column_null :admin_users, :tenant_id, false
  end
end
