class AddProfileGovernanceCheckConstraints < ActiveRecord::Migration[7.1]
  def change
    add_check_constraint :profiles,
                         "axis IN ('vertical', 'horizontal')",
                         name: "profiles_axis_allowed",
                         validate: false

    add_check_constraint :profiles,
                         <<~SQL.squish,
                           (
                             axis = 'vertical'
                             AND vertical_profile_id IS NULL
                             AND position IS NOT NULL
                           )
                           OR
                           (
                             axis = 'horizontal'
                             AND vertical_profile_id IS NOT NULL
                             AND position IS NULL
                           )
                         SQL
                         name: "profiles_axis_shape",
                         validate: false

    add_check_constraint :admin_users,
                         "super_admin = TRUE OR profile_id IS NOT NULL",
                         name: "admin_users_profile_required_unless_system_admin",
                         validate: false
  end
end
