class CanonicalizeBuiltinVerticalProfiles < ActiveRecord::Migration[7.1]
  def up
    say_with_time "Canonicalizing Tenant Owner and Agent profiles" do
      select_all("SELECT id FROM tenants").each do |tenant|
        tenant_id = tenant["id"].to_i
        canonicalize_pair(
          tenant_id: tenant_id,
          canonical_key: "tenant_owner",
          canonical_name: "Tenant Owner",
          legacy_key: "administrador",
          legacy_name: "Administrador",
          position: 0,
          permissions_sql: "'{\"admin\": true}'::jsonb"
        )
        canonicalize_pair(
          tenant_id: tenant_id,
          canonical_key: "agent",
          canonical_name: "Agent",
          legacy_key: "corretor",
          legacy_name: "Corretor",
          position: 10_000,
          permissions_sql: "'{}'::jsonb"
        )
      end
    end
  end

  def down
    # Canonical keys are forward-compatible. Do not recreate legacy keys.
  end

  private

  def canonicalize_pair(tenant_id:, canonical_key:, canonical_name:, legacy_key:, legacy_name:, position:, permissions_sql:)
    canonical_id = select_value(<<~SQL.squish)
      SELECT id FROM profiles
      WHERE tenant_id = #{tenant_id}
        AND key = '#{canonical_key}'
      LIMIT 1
    SQL

    legacy_id = select_value(<<~SQL.squish)
      SELECT id FROM profiles
      WHERE tenant_id = #{tenant_id}
        AND key = '#{legacy_key}'
      LIMIT 1
    SQL

    if canonical_id.blank? && legacy_id.present?
      execute(<<~SQL.squish)
        UPDATE profiles
        SET key = '#{canonical_key}',
            name = '#{canonical_name}',
            axis = 'vertical',
            vertical_profile_id = NULL,
            position = #{position},
            locked = TRUE,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = #{legacy_id.to_i}
      SQL
      return
    end

    if canonical_id.blank?
      execute(<<~SQL.squish)
        INSERT INTO profiles (tenant_id, name, key, axis, vertical_profile_id, position, locked, permissions, active, created_at, updated_at)
        VALUES (#{tenant_id}, '#{canonical_name}', '#{canonical_key}', 'vertical', NULL, #{position}, TRUE, #{permissions_sql}, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
      return
    end

    canonical_id = canonical_id.to_i
    execute(<<~SQL.squish)
      UPDATE profiles
      SET name = '#{canonical_name}',
          axis = 'vertical',
          vertical_profile_id = NULL,
          position = #{position},
          locked = TRUE,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = #{canonical_id}
    SQL

    return if legacy_id.blank?

    legacy_id = legacy_id.to_i
    execute("UPDATE admin_users SET profile_id = #{canonical_id} WHERE profile_id = #{legacy_id}")
    execute("UPDATE admin_users SET horizontal_profile_id = NULL WHERE horizontal_profile_id = #{legacy_id}")
    execute("UPDATE profiles SET vertical_profile_id = #{canonical_id} WHERE vertical_profile_id = #{legacy_id}")
    execute(<<~SQL.squish)
      UPDATE profiles
      SET key = NULL,
          name = '#{legacy_name} legado',
          locked = FALSE,
          position = #{position == 0 ? 100 : 9_900},
          updated_at = CURRENT_TIMESTAMP
      WHERE id = #{legacy_id}
    SQL
  end
end
