class AddAdminAreaNameToLayoutSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :layout_settings, :admin_area_name, :string, default: "Admin", null: false
  end
end
