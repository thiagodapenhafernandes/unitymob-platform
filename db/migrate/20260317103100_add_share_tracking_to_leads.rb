class AddShareTrackingToLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :leads, :share_token, :string
    add_reference :leads, :shared_by_admin_user, foreign_key: { to_table: :admin_users }

    add_index :leads, :share_token
  end
end
