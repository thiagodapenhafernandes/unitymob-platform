class CreateGoogleMapsIntegrationSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :google_maps_integration_settings do |t|
      t.references :tenant, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.text :api_key
      t.string :default_display_mode, null: false, default: "approximate"
      t.integer :approximate_radius_meters, null: false, default: 220
      t.integer :default_zoom, null: false, default: 15
      t.boolean :satellite_enabled, null: false, default: true
      t.boolean :street_view_enabled, null: false, default: true
      t.boolean :external_link_enabled, null: false, default: true

      t.timestamps
    end

    add_column :habitations, :public_map_display_mode, :string, null: false, default: "inherit"
    add_column :habitations, :public_street_view_mode, :string, null: false, default: "inherit"
  end
end
