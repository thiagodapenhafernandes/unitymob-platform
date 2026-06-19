class AddHierarchyPositionToAdminUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :admin_users, :hierarchy_position, :integer
    add_index :admin_users, [:manager_id, :hierarchy_position]
  end
end
