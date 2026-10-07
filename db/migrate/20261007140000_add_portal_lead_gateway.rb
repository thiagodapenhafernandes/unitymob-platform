class AddPortalLeadGateway < ActiveRecord::Migration[7.1]
  def change
    add_column :portal_integrations, :lead_route_key, :string
    add_index :portal_integrations, :lead_route_key, unique: true
    add_column :portal_integrations, :lead_gateway_synced_at, :datetime
    add_column :portal_integrations, :lead_gateway_error, :string
  end
end
