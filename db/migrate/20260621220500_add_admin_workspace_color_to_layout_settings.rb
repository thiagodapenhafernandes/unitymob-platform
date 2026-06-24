class AddAdminWorkspaceColorToLayoutSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :layout_settings, :admin_workspace_color, :string, default: "#EEF2F7", null: false unless column_exists?(:layout_settings, :admin_workspace_color)
  end
end
