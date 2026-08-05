class RenamePublicSiteThemeKeys < ActiveRecord::Migration[7.1]
  def up
    change_column_default :tenants, :public_site_theme, "saluteimoveis"

    execute <<~SQL.squish
      UPDATE tenants
         SET public_site_theme = 'saluteimoveis'
       WHERE public_site_theme IS NULL
          OR public_site_theme = ''
          OR public_site_theme IN ('classic', 'editorial', 'compact')
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE tenants
         SET public_site_theme = 'saluteimoveis'
       WHERE public_site_theme IS NULL
          OR public_site_theme = ''
    SQL

    change_column_default :tenants, :public_site_theme, "saluteimoveis"
  end
end
