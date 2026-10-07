class AddGrupozapRoutes < ActiveRecord::Migration[7.1]
  def change
    add_index :webhook_routes, :client_key, unique: true, where: "provider = 'grupozap'", name: "index_grupozap_route_identity"
    add_index :webhook_events, [:webhook_route_id, :external_id], unique: true,
      where: "provider = 'grupozap'", name: "index_grupozap_delivery_identity"
  end
end
