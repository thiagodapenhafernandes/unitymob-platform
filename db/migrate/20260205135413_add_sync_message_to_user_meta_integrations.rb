class AddSyncMessageToUserMetaIntegrations < ActiveRecord::Migration[7.1]
  def change
    add_column :user_meta_integrations, :sync_message, :string
  end
end
