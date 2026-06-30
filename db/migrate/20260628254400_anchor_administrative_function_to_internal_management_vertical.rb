class AnchorAdministrativeFunctionToInternalManagementVertical < ActiveRecord::Migration[7.1]
  INTERNAL_MANAGEMENT_PROFILE_NAME = "Gestão Interna".freeze
  INTERNAL_MANAGEMENT_PROFILE_POSITION = 100

  ADMINISTRATIVE_VERTICAL_PERMISSIONS = {
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
      internal_profile_id = ensure_internal_management_profile!(tenant_id)
      administrative_profile_id = find_administrative_profile_id(tenant_id)
      next if administrative_profile_id.blank?

      attach_administrative_function!(administrative_profile_id, internal_profile_id)
      migrate_administrative_users!(tenant_id, administrative_profile_id, internal_profile_id)
      detach_invalid_manager_links!(tenant_id)
    end
  end

  def down
    select_all("SELECT id FROM tenants ORDER BY id").each do |tenant|
      tenant_id = tenant["id"].to_i
      manager_id = select_value(<<~SQL.squish)
        SELECT id
        FROM profiles
        WHERE tenant_id = #{tenant_id}
          AND key = 'gerente'
          AND axis = 'vertical'
        LIMIT 1
      SQL
      administrative_id = find_administrative_profile_id(tenant_id)
      next if manager_id.blank? || administrative_id.blank?

      execute(<<~SQL.squish)
        UPDATE profiles
        SET vertical_profile_id = #{manager_id.to_i},
            updated_at = CURRENT_TIMESTAMP
        WHERE id = #{administrative_id.to_i}
      SQL
    end
  end

  private

  def ensure_internal_management_profile!(tenant_id)
    existing_id = select_value(<<~SQL.squish)
      SELECT id
      FROM profiles
      WHERE tenant_id = #{tenant_id}
        AND axis = 'vertical'
        AND LOWER(name) = LOWER('#{INTERNAL_MANAGEMENT_PROFILE_NAME}')
      LIMIT 1
    SQL

    if existing_id.present?
      existing_id = existing_id.to_i
      execute(<<~SQL.squish)
        UPDATE profiles
        SET vertical_profile_id = NULL,
            position = COALESCE(position, #{next_available_vertical_position(tenant_id)}),
            locked = FALSE,
            permissions = CASE WHEN permissions = '{}'::jsonb THEN '#{permissions_json}'::jsonb ELSE permissions END,
            active = TRUE,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = #{existing_id}
      SQL
      return existing_id
    end

    select_value(<<~SQL.squish).to_i
      INSERT INTO profiles (tenant_id, name, key, axis, vertical_profile_id, position, locked, permissions, active, created_at, updated_at)
      VALUES (#{tenant_id}, '#{INTERNAL_MANAGEMENT_PROFILE_NAME}', NULL, 'vertical', NULL, #{next_available_vertical_position(tenant_id)}, FALSE, '#{permissions_json}'::jsonb, TRUE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      RETURNING id
    SQL
  end

  def find_administrative_profile_id(tenant_id)
    select_value(<<~SQL.squish)&.to_i
      SELECT id
      FROM profiles
      WHERE tenant_id = #{tenant_id}
        AND key = 'administrativo'
        AND axis = 'horizontal'
      LIMIT 1
    SQL
  end

  def attach_administrative_function!(administrative_profile_id, internal_profile_id)
    execute(<<~SQL.squish)
      UPDATE profiles
      SET vertical_profile_id = #{internal_profile_id},
          position = NULL,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = #{administrative_profile_id}
    SQL
  end

  def migrate_administrative_users!(tenant_id, administrative_profile_id, internal_profile_id)
    execute(<<~SQL.squish)
      UPDATE admin_users AS users
      SET profile_id = #{internal_profile_id},
          manager_id = CASE
            WHEN users.manager_id IS NULL THEN NULL
            WHEN EXISTS (
              SELECT 1
              FROM admin_users managers
              JOIN profiles manager_profiles
                ON manager_profiles.id = managers.profile_id
               AND manager_profiles.tenant_id = managers.tenant_id
              JOIN profiles selected_profile
                ON selected_profile.id = #{internal_profile_id}
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
        AND users.horizontal_profile_id = #{administrative_profile_id}
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

    candidate = INTERNAL_MANAGEMENT_PROFILE_POSITION
    candidate += 100 while used.include?(candidate) && candidate < 9_900
    candidate
  end

  def permissions_json
    @permissions_json ||= connection.quote(ADMINISTRATIVE_VERTICAL_PERMISSIONS.to_json)[1..-2]
  end
end
