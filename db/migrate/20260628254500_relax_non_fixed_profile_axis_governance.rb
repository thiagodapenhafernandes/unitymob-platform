class RelaxNonFixedProfileAxisGovernance < ActiveRecord::Migration[7.1]
  CONSTRAINT_NAME = "profiles_builtin_axis_governance"

  def change
    remove_check_constraint :profiles, name: CONSTRAINT_NAME, if_exists: true

    add_check_constraint :profiles,
                         <<~SQL.squish,
                           key IS NULL
                           OR key NOT IN ('tenant_owner', 'agent')
                           OR (
                             key IN ('tenant_owner', 'agent')
                             AND axis = 'vertical'
                             AND vertical_profile_id IS NULL
                             AND position IS NOT NULL
                           )
                         SQL
                         name: CONSTRAINT_NAME,
                         validate: false
  end
end
