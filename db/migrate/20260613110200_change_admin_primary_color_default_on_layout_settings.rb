class ChangeAdminPrimaryColorDefaultOnLayoutSettings < ActiveRecord::Migration[7.0]
  def change
    change_column_default :layout_settings, :admin_primary_color, from: "#2563EB", to: "#365F8F"
  end
end
