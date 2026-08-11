class ApplyAccessProfilePresets < ActiveRecord::Migration[7.1]
  PROFILE_PRESETS = {
    "Administrador" => {
      "admin" => true
    },
    "Corretor" => {
      "admin" => false,
      "dashboard" => { "view" => true },
      "imoveis" => { "view" => true, "media" => true, "create" => false, "edit" => false, "delete" => false, "scope" => "own" },
      "leads" => { "view" => true, "create" => true, "edit" => true, "delete" => false, "scope" => "own" },
      "comercial" => { "view" => true, "manage" => true, "scope" => "own" },
      "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "own" },
      "captacoes" => { "view" => true, "manage" => true, "review" => false, "publish" => true, "scope" => "own" }
    },
    "Administrativo" => {
      "admin" => false,
      "dashboard" => { "view" => true },
      "imoveis" => { "view" => true, "media" => true, "create" => true, "edit" => true, "delete" => false, "scope" => "all" },
      "leads" => { "view" => true, "create" => true, "edit" => true, "delete" => false, "scope" => "all" },
      "comercial" => { "view" => true, "manage" => true, "scope" => "all" },
      "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "all" },
      "whatsapp_campaigns" => { "view" => true, "manage" => true, "scope" => "all" },
      "captacoes" => { "view" => true, "manage" => true, "review" => true, "publish" => true, "scope" => "all" },
      "captacao_dashboard" => { "view" => true },
      "agenda_fotografia" => { "view" => true, "manage" => true },
      "marketing" => { "manage" => true },
      "automacoes" => { "manage" => true }
    },
    "Gerente" => {
      "admin" => false,
      "dashboard" => { "view" => true },
      "imoveis" => { "view" => true, "media" => true, "create" => true, "edit" => true, "delete" => false, "scope" => "team" },
      "leads" => { "view" => true, "create" => true, "edit" => true, "delete" => false, "scope" => "team" },
      "comercial" => { "view" => true, "manage" => true, "scope" => "team" },
      "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "team" },
      "whatsapp_campaigns" => { "view" => true, "manage" => true, "scope" => "team" },
      "captacoes" => { "view" => true, "manage" => true, "review" => true, "publish" => true, "scope" => "team" },
      "captacao_dashboard" => { "view" => true }
    }
  }.freeze

  PHOTOGRAPHER_PERMISSIONS = {
    "admin" => false,
    "dashboard" => { "view" => false },
    "agenda_fotografia" => { "view" => true, "manage" => false }
  }.freeze

  def up
    PROFILE_PRESETS.each do |name, permissions|
      upsert_profile(name, permissions)
    end

    execute(<<~SQL)
      UPDATE admin_users
      SET profile_id = administrative_profiles.id,
          updated_at = CURRENT_TIMESTAMP
      FROM profiles photographer_profiles, profiles administrative_profiles
      WHERE admin_users.profile_id = photographer_profiles.id
        AND photographer_profiles.name = 'Fotógrafo'
        AND administrative_profiles.name = 'Administrativo'
    SQL

    execute(<<~SQL)
      DELETE FROM profiles
      WHERE name = 'Fotógrafo'
        AND NOT EXISTS (
          SELECT 1 FROM admin_users WHERE admin_users.profile_id = profiles.id
        )
    SQL
  end

  def down
    upsert_profile("Fotógrafo", PHOTOGRAPHER_PERMISSIONS)
  end

  private

  def upsert_profile(name, permissions)
    quoted_name = connection.quote(name)
    permissions_json = connection.quote(permissions.to_json)

    execute(<<~SQL)
      UPDATE profiles
      SET active = TRUE,
          permissions = #{permissions_json}::jsonb,
          updated_at = CURRENT_TIMESTAMP
      WHERE name = #{quoted_name}
    SQL

    execute(<<~SQL)
      INSERT INTO profiles (name, active, permissions, created_at, updated_at)
      SELECT #{quoted_name}, TRUE, #{permissions_json}::jsonb, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      WHERE NOT EXISTS (
        SELECT 1 FROM profiles WHERE name = #{quoted_name}
      )
    SQL
  end
end
