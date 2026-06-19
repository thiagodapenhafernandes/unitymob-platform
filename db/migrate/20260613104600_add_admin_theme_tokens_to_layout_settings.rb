class AddAdminThemeTokensToLayoutSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :layout_settings, :admin_surface_color, :string, default: "#FFFFFF", null: false unless column_exists?(:layout_settings, :admin_surface_color)
    add_column :layout_settings, :admin_header_color, :string, default: "#EEF2F7", null: false unless column_exists?(:layout_settings, :admin_header_color)
    add_column :layout_settings, :admin_ink_color, :string, default: "#1F2733", null: false unless column_exists?(:layout_settings, :admin_ink_color)
  end
end
