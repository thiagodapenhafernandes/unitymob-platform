class AddImovelwebAdvertiserToRoutes < ActiveRecord::Migration[7.1]
  def change
    add_column :webhook_routes, :imovelweb_advertiser_code, :string
    add_index :webhook_routes, [:imovelweb_environment, :imovelweb_advertiser_code], unique: true,
      where: "provider = 'imovelweb' AND imovelweb_advertiser_code IS NOT NULL", name: "index_imovelweb_route_advertiser"
  end
end
