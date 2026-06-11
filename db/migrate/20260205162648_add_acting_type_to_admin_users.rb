class AddActingTypeToAdminUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :admin_users, :acting_type, :integer
  end
end
