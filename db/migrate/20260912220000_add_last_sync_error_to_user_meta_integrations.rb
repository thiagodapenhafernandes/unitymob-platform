class AddLastSyncErrorToUserMetaIntegrations < ActiveRecord::Migration[7.1]
  def change
    add_column :user_meta_integrations, :last_sync_error, :text
  end
end
