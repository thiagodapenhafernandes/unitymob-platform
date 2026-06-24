class RenameAdminAreaDefaultToPlatform < ActiveRecord::Migration[7.0]
  def up
    change_column_default :layout_settings, :admin_area_name, from: "Admin", to: "Plataforma"
    execute <<~SQL.squish
      UPDATE layout_settings
      SET admin_area_name = 'Plataforma'
      WHERE admin_area_name IS NULL
         OR btrim(admin_area_name) = ''
         OR admin_area_name = 'Admin'
    SQL
  end

  def down
    change_column_default :layout_settings, :admin_area_name, from: "Plataforma", to: "Admin"
    execute <<~SQL.squish
      UPDATE layout_settings
      SET admin_area_name = 'Admin'
      WHERE admin_area_name = 'Plataforma'
    SQL
  end
end
