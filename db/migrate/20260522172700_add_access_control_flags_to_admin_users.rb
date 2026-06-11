class AddAccessControlFlagsToAdminUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :admin_users, :require_ip_allowlist, :boolean, null: false, default: false
    add_column :admin_users, :require_trusted_device, :boolean, null: false, default: false
  end
end
