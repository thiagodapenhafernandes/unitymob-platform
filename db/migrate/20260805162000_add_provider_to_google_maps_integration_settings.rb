class AddProviderToGoogleMapsIntegrationSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :google_maps_integration_settings, :provider, :string, null: false, default: "google"
    change_column_default :google_maps_integration_settings, :provider, from: "google", to: "leaflet"
  end
end
