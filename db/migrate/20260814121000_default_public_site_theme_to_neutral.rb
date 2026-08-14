class DefaultPublicSiteThemeToNeutral < ActiveRecord::Migration[7.1]
  def up
    return unless column_exists?(:tenants, :public_site_theme)

    change_column_default :tenants, :public_site_theme, from: "saluteimoveis", to: "default"

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

    change_column_default :tenants, :public_site_theme, from: "default", to: "saluteimoveis"
  end
end
