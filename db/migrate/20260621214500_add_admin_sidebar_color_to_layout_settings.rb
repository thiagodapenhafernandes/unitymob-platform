class AddAdminSidebarColorToLayoutSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :layout_settings, :admin_sidebar_color, :string, default: "#FFFFFF", null: false unless column_exists?(:layout_settings, :admin_sidebar_color)
  end
end
