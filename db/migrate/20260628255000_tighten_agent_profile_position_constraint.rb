class TightenAgentProfilePositionConstraint < ActiveRecord::Migration[7.1]
  CONSTRAINT_NAME = "profiles_vertical_position_governance"

  def change
    remove_check_constraint :profiles, name: CONSTRAINT_NAME, if_exists: true

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
                         name: CONSTRAINT_NAME,
                         validate: false
  end
end
