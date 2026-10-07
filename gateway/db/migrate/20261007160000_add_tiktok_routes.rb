class AddTiktokRoutes < ActiveRecord::Migration[7.1]
  def change
    create_table :tiktok_oauth_states do |t|
      t.string :state_digest, null: false
      t.string :return_url, null: false
      t.datetime :expires_at, null: false
    end
    add_index :tiktok_oauth_states, :state_digest, unique: true
    add_index :tiktok_oauth_states, :expires_at
    add_column :webhook_routes, :advertiser_id, :string
    add_column :webhook_events, :advertiser_id, :string
    add_index :webhook_routes, :advertiser_id, unique: true, where: "provider = 'tiktok'", name: "index_tiktok_route_identity"
    add_index :webhook_events, [:advertiser_id, :external_id], unique: true, where: "provider = 'tiktok'", name: "index_tiktok_delivery_identity"
  end
end
