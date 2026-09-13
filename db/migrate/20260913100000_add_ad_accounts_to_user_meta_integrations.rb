class AddAdAccountsToUserMetaIntegrations < ActiveRecord::Migration[7.1]
  def change
    add_column :user_meta_integrations, :ad_accounts, :jsonb, default: {}, null: false
  end
end
