class AddAdAccountToMetaIntegrations < ActiveRecord::Migration[7.1]
  def change
    add_column :user_meta_integrations, :ad_account_id, :string
    add_column :user_meta_integrations, :ad_account_name, :string
  end
end
