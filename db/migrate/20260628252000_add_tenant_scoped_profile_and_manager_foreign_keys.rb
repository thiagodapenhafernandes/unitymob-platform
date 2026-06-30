class AddTenantScopedProfileAndManagerForeignKeys < ActiveRecord::Migration[7.1]
  def change
    add_index :profiles, [:id, :tenant_id],
              unique: true,
              name: "index_profiles_on_id_and_tenant_id",
              if_not_exists: true

    add_index :admin_users, [:id, :tenant_id],
              unique: true,
              name: "index_admin_users_on_id_and_tenant_id",
              if_not_exists: true

    add_foreign_key :profiles,
                    :profiles,
                    column: [:vertical_profile_id, :tenant_id],
                    primary_key: [:id, :tenant_id],
                    name: "fk_profiles_vertical_profile_same_tenant",
                    validate: false

    add_foreign_key :admin_users,
                    :profiles,
                    column: [:profile_id, :tenant_id],
                    primary_key: [:id, :tenant_id],
                    name: "fk_admin_users_profile_same_tenant",
                    validate: false

    add_foreign_key :admin_users,
                    :profiles,
                    column: [:horizontal_profile_id, :tenant_id],
                    primary_key: [:id, :tenant_id],
                    name: "fk_admin_users_horizontal_profile_same_tenant",
                    validate: false

    add_foreign_key :admin_users,
                    :admin_users,
                    column: [:manager_id, :tenant_id],
                    primary_key: [:id, :tenant_id],
                    name: "fk_admin_users_manager_same_tenant",
                    validate: false
  end
end
