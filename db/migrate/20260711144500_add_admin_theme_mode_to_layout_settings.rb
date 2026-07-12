class AddAdminThemeModeToLayoutSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :layout_settings, :admin_theme_mode, :string, default: "light", null: false
  end
end
