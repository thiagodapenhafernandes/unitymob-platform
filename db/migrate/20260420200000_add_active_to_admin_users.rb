class AddActiveToAdminUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :admin_users, :active, :boolean, default: true, null: false
    add_index :admin_users, :active
  end
end
