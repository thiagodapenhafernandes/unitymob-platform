class AddProfilePositionGovernanceCheckConstraints < ActiveRecord::Migration[7.1]
  def change
    add_check_constraint :profiles,
                         "locked = FALSE OR key IN ('tenant_owner', 'agent')",
                         name: "profiles_locked_only_for_builtin_verticals",
                         validate: false

    add_check_constraint :profiles,
                         <<~SQL.squish,
                           axis <> 'vertical'
                           OR (
                             key = 'tenant_owner'
                             AND position = 0
                             AND locked = TRUE
                             AND vertical_profile_id IS NULL
                           )
                           OR (
                             key = 'agent'
                             AND position = 10000
                             AND locked = TRUE
                             AND vertical_profile_id IS NULL
                           )
                           OR (
                             (key IS NULL OR key NOT IN ('tenant_owner', 'agent'))
                             AND position > 0
                             AND position < 10000
                             AND vertical_profile_id IS NULL
                           )
                         SQL
                         name: "profiles_vertical_position_governance",
                         validate: false
  end
end
