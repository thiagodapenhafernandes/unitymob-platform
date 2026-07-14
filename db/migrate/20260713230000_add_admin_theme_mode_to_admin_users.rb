class AddAdminThemeModeToAdminUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :admin_users, :admin_theme_mode, :string, null: false, default: "light"
  end
end
