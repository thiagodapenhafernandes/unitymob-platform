class AddImovelwebRoutes < ActiveRecord::Migration[7.1]
  def change
    add_column :webhook_routes, :imovelweb_client_code, :string
    add_column :webhook_routes, :imovelweb_environment, :string
    add_index :webhook_routes, :client_key, unique: true, where: "provider = 'imovelweb'", name: "index_imovelweb_route_key"
    add_index :webhook_routes, [:imovelweb_environment, :imovelweb_client_code], unique: true,
      where: "provider = 'imovelweb'", name: "index_imovelweb_route_client"
    add_index :webhook_events, [:webhook_route_id, :external_id], unique: true,
      where: "provider = 'imovelweb'", name: "index_imovelweb_gateway_event"
  end
end
