class AddListingSyncStatusToImovelwebConnections < ActiveRecord::Migration[7.1]
  def change
    add_column :imovelweb_connections, :listings_synced_at, :datetime
    add_column :imovelweb_connections, :listing_sync_error, :string
  end
end
