class ConvertAdministrativeProfileToHorizontal < ActiveRecord::Migration[7.1]
  AXIS_CONSTRAINT = "profiles_builtin_axis_governance"

  MANAGER_PERMISSIONS = {
    "admin" => false,
    "dashboard" => { "view" => true },
    "imoveis" => { "view" => true, "manage" => true, "scope" => "team" },
    "leads" => { "view" => true, "manage" => true, "scope" => "team" },
    "comercial" => { "view" => true, "manage" => true, "scope" => "team" },
    "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "team" },
    "whatsapp_campaigns" => { "view" => true, "manage" => true, "scope" => "team" },
    "captacoes" => { "view" => true, "manage" => true, "review" => true, "publish" => true, "scope" => "team" },
    "captacao_dashboard" => { "view" => true }
  }.freeze

  ADMINISTRATIVE_PERMISSIONS = {
    "admin" => false,
    "dashboard" => { "view" => true },
    "imoveis" => { "view" => true, "manage" => true, "scope" => "all" },
    "leads" => { "view" => true, "manage" => true, "scope" => "all" },
    "comercial" => { "view" => true, "manage" => true, "scope" => "all" },
    "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "all" },
    "whatsapp_campaigns" => { "view" => true, "manage" => true, "scope" => "all" },
    "captacoes" => { "view" => true, "manage" => true, "review" => true, "publish" => true, "scope" => "all" },
    "captacao_dashboard" => { "view" => true },
    "agenda_fotografia" => { "view" => true, "manage" => true },
    "marketing" => { "manage" => true },
    "automacoes" => { "manage" => true }
  }.freeze

  def up
    select_all("SELECT id FROM tenants ORDER BY id").each do |tenant|
      tenant_id = tenant["id"].to_i
      manager_id = ensure_manager_profile!(tenant_id)
      administrative_id = ensure_administrative_profile!(tenant_id, manager_id)

      migrate_administrative_users!(tenant_id, manager_id, administrative_id)
      detach_invalid_manager_links!(tenant_id)
    end

    add_check_constraint :profiles,
                         <<~SQL.squish,
                           key IS NULL
                           OR (key = 'administrativo' AND axis = 'horizontal' AND vertical_profile_id IS NOT NULL AND position IS NULL)
                           OR (key <> 'administrativo' AND key NOT IN ('tenant_owner', 'gerente', 'agent'))
                           OR (key IN ('tenant_owner', 'gerente', 'agent') AND axis = 'vertical' AND vertical_profile_id IS NULL AND position IS NOT NULL)
                         SQL
                         name: AXIS_CONSTRAINT,
                         validate: false
  end

  def down
    remove_check_constraint :profiles, name: AXIS_CONSTRAINT, if_exists: true
  end

  private

  def ensure_manager_profile!(tenant_id)
    manager_id = select_value(<<~SQL.squish)
      SELECT id
      FROM profiles
      WHERE tenant_id = #{tenant_id}
        AND (key = 'gerente' OR (name = 'Gerente' AND axis = 'vertical'))
      ORDER BY CASE WHEN key = 'gerente' THEN 0 ELSE 1 END, id
      LIMIT 1
    SQL

    if manager_id.present?
      manager_id = manager_id.to_i
      execute(<<~SQL.squish)
        UPDATE profiles
        SET key = 'gerente',
            name = 'Gerente',
            axis = 'vertical',
            vertical_profile_id = NULL,
            position = COALESCE(position, #{next_available_vertical_position(tenant_id)}),
            locked = FALSE,
            permissions = CASE WHEN permissions = '{}'::jsonb THEN '#{manager_permissions_json}'::jsonb ELSE permissions END,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = #{manager_id}
      SQL
      return manager_id
    end

    select_value(<<~SQL.squish).to_i
      INSERT INTO profiles (tenant_id, name, key, axis, vertical_profile_id, position, locked, permissions, active, created_at, updated_at)
      VALUES (#{tenant_id}, 'Gerente', 'gerente', 'vertical', NULL, #{next_available_vertical_position(tenant_id)}, FALSE, '#{manager_permissions_json}'::jsonb, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      RETURNING id
    SQL
  end

  def ensure_administrative_profile!(tenant_id, manager_id)
    administrative_id = select_value(<<~SQL.squish)
      SELECT id
      FROM profiles
      WHERE tenant_id = #{tenant_id}
        AND (key = 'administrativo' OR name = 'Administrativo')
      ORDER BY CASE WHEN key = 'administrativo' THEN 0 ELSE 1 END, id
      LIMIT 1
    SQL

    if administrative_id.present?
      administrative_id = administrative_id.to_i
      execute(<<~SQL.squish)
        UPDATE profiles
        SET vertical_profile_id = #{manager_id},
            updated_at = CURRENT_TIMESTAMP
        WHERE tenant_id = #{tenant_id}
          AND vertical_profile_id = #{administrative_id}
      SQL
      execute(<<~SQL.squish)
        UPDATE profiles
        SET key = 'administrativo',
            name = 'Administrativo',
            axis = 'horizontal',
            vertical_profile_id = #{manager_id},
            position = NULL,
            locked = FALSE,
            permissions = CASE WHEN permissions = '{}'::jsonb THEN '#{administrative_permissions_json}'::jsonb ELSE permissions END,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = #{administrative_id}
      SQL
      return administrative_id
    end

    select_value(<<~SQL.squish).to_i
      INSERT INTO profiles (tenant_id, name, key, axis, vertical_profile_id, position, locked, permissions, active, created_at, updated_at)
      VALUES (#{tenant_id}, 'Administrativo', 'administrativo', 'horizontal', #{manager_id}, NULL, FALSE, '#{administrative_permissions_json}'::jsonb, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      RETURNING id
    SQL
  end

  def migrate_administrative_users!(tenant_id, manager_id, administrative_id)
    execute(<<~SQL.squish)
      UPDATE admin_users AS users
      SET profile_id = #{manager_id},
          horizontal_profile_id = #{administrative_id},
          manager_id = CASE
            WHEN users.manager_id IS NULL THEN NULL
            WHEN EXISTS (
              SELECT 1
              FROM admin_users managers
              JOIN profiles manager_profiles
                ON manager_profiles.id = managers.profile_id
               AND manager_profiles.tenant_id = managers.tenant_id
              JOIN profiles selected_profile
                ON selected_profile.id = #{manager_id}
               AND selected_profile.tenant_id = users.tenant_id
              WHERE managers.id = users.manager_id
                AND managers.tenant_id = users.tenant_id
                AND manager_profiles.axis = 'vertical'
                AND manager_profiles.position < selected_profile.position
            ) THEN users.manager_id
            ELSE NULL
          END,
          updated_at = CURRENT_TIMESTAMP
      WHERE users.tenant_id = #{tenant_id}
        AND (users.profile_id = #{administrative_id} OR users.horizontal_profile_id = #{administrative_id})
    SQL
  end

  def detach_invalid_manager_links!(tenant_id)
    execute(<<~SQL.squish)
      UPDATE admin_users AS children
      SET manager_id = NULL,
          updated_at = CURRENT_TIMESTAMP
      FROM admin_users AS managers,
           profiles AS manager_profiles,
           profiles AS child_profiles
      WHERE children.tenant_id = #{tenant_id}
        AND children.manager_id = managers.id
        AND manager_profiles.id = managers.profile_id
        AND manager_profiles.tenant_id = managers.tenant_id
        AND child_profiles.id = children.profile_id
        AND child_profiles.tenant_id = children.tenant_id
        AND manager_profiles.position >= child_profiles.position
    SQL
  end

  def next_available_vertical_position(tenant_id)
    used = select_values(<<~SQL.squish).map(&:to_i)
      SELECT position
      FROM profiles
      WHERE tenant_id = #{tenant_id}
        AND axis = 'vertical'
        AND position IS NOT NULL
    SQL

    candidate = 500
    candidate += 100 while used.include?(candidate) && candidate < 9_900
    candidate
  end

  def manager_permissions_json
    @manager_permissions_json ||= connection.quote(MANAGER_PERMISSIONS.to_json)[1..-2]
  end

  def administrative_permissions_json
    @administrative_permissions_json ||= connection.quote(ADMINISTRATIVE_PERMISSIONS.to_json)[1..-2]
  end
end
