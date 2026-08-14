class DefaultPublicSiteThemeToNeutral < ActiveRecord::Migration[7.1]
  def up
    return unless column_exists?(:tenants, :public_site_theme)

    begin
      change_column_default :tenants, :public_site_theme, from: "saluteimoveis", to: "default"
    rescue ActiveRecord::StatementInvalid => error
      raise unless insufficient_privilege?(error)

      say "Skipping tenants.public_site_theme default change because the database user is not the table owner"
    end

    execute <<~SQL.squish
      UPDATE tenants
         SET public_site_theme = 'default', updated_at = CURRENT_TIMESTAMP
       WHERE public_site_theme = 'saluteimoveis'
         AND COALESCE(slug, '') <> 'saluteimoveis'
         AND LOWER(COALESCE(name, '')) NOT LIKE '%salute%'
    SQL
  end

  def down
    return unless column_exists?(:tenants, :public_site_theme)

    begin
      change_column_default :tenants, :public_site_theme, from: "default", to: "saluteimoveis"
    rescue ActiveRecord::StatementInvalid => error
      raise unless insufficient_privilege?(error)

      say "Skipping tenants.public_site_theme default rollback because the database user is not the table owner"
    end
  end

  def insufficient_privilege?(error)
    error.cause.is_a?(PG::InsufficientPrivilege) || error.message.include?("must be owner of table tenants")
  end
end
