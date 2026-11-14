class AddDisconnectedAtToUserMetaIntegrations < ActiveRecord::Migration[7.1]
  def change
    add_column :user_meta_integrations, :disconnected_at, :datetime
  end
end
