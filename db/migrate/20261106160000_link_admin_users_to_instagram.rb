class LinkAdminUsersToInstagram < ActiveRecord::Migration[7.1]
  def change
    add_column :admin_users, :instagram_username, :string, limit: 30
    add_column :admin_users, :instagram_direct_ids, :jsonb, default: {}, null: false
    add_index :admin_users, [:tenant_id, :instagram_username], unique: true,
      where: "instagram_username IS NOT NULL"
  end
end
