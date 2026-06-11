class AddSyncStatusToUserMetaIntegrations < ActiveRecord::Migration[7.1]
  def change
    add_column :user_meta_integrations, :sync_status, :string
    add_column :user_meta_integrations, :sync_progress, :integer
    add_column :user_meta_integrations, :last_synced_at, :datetime
  end
end
