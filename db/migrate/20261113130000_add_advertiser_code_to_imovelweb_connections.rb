class AddAdvertiserCodeToImovelwebConnections < ActiveRecord::Migration[7.1]
  def change
    add_column :imovelweb_connections, :advertiser_code, :string, limit: 128
    add_index :imovelweb_connections, [:tenant_id, :environment, :advertiser_code], unique: true,
      where: 'advertiser_code IS NOT NULL', name: 'index_imovelweb_advertiser_per_tenant'
  end
end
