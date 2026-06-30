class BackfillAdminUserVerticalProfiles < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      UPDATE admin_users
      SET profile_id = COALESCE(
        CASE WHEN admin_users.role = 1 THEN tenant_owner_profiles.id END,
        administrative_profiles.id,
        agent_profiles.id,
        fallback_profiles.id
      )
      FROM tenants
      LEFT JOIN profiles tenant_owner_profiles
        ON tenant_owner_profiles.tenant_id = tenants.id
       AND tenant_owner_profiles.axis = 'vertical'
       AND tenant_owner_profiles.key IN ('tenant_owner', 'administrador')
      LEFT JOIN profiles administrative_profiles
        ON administrative_profiles.tenant_id = tenants.id
       AND administrative_profiles.axis = 'vertical'
       AND administrative_profiles.key = 'administrativo'
      LEFT JOIN profiles agent_profiles
        ON agent_profiles.tenant_id = tenants.id
       AND agent_profiles.axis = 'vertical'
       AND agent_profiles.key IN ('agent', 'corretor')
      LEFT JOIN profiles fallback_profiles
        ON fallback_profiles.id = (
          SELECT profiles.id
          FROM profiles
          WHERE profiles.tenant_id = tenants.id
            AND profiles.axis = 'vertical'
          ORDER BY profiles.position ASC, profiles.id ASC
          LIMIT 1
        )
      WHERE admin_users.tenant_id = tenants.id
        AND admin_users.super_admin = FALSE
        AND admin_users.profile_id IS NULL
    SQL
  end

  def down
    # Data backfill only. Keeping profile assignments is safer than removing them.
  end
end
