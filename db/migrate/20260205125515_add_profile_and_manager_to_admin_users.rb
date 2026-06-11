class AddProfileAndManagerToAdminUsers < ActiveRecord::Migration[7.1]
  def change
    add_reference :admin_users, :profile, null: true, foreign_key: true
    add_reference :admin_users, :manager, null: true, foreign_key: { to_table: :admin_users }
  end
end
