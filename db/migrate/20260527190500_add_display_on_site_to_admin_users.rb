class AddDisplayOnSiteToAdminUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :admin_users, :display_on_site, :boolean, null: false, default: true
    add_index :admin_users, :display_on_site
  end
end
