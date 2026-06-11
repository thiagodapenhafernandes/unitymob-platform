class AddVistaFieldsToAdminUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :admin_users, :vista_id, :string
    add_index :admin_users, :vista_id
    add_column :admin_users, :creci, :string
    add_column :admin_users, :phone, :string
    add_column :admin_users, :biography, :text
    add_column :admin_users, :birth_date, :date
    add_column :admin_users, :city, :string
  end
end
