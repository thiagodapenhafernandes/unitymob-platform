class AddSelfServiceToImovelwebConnections < ActiveRecord::Migration[7.1]
  def change
    add_column :imovelweb_connections, :authorization_requested_at, :datetime
    add_column :imovelweb_connections, :gateway_synced_at, :datetime
    add_column :imovelweb_connections, :connection_error, :string
  end
end
