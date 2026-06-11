class CreatePortalIntegrationEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :portal_integration_events do |t|
      t.string :portal, null: false
      t.references :habitation, null: true, foreign_key: true
      t.string :habitation_code
      t.string :external_listing_id
      t.string :event_type, null: false
      t.string :normalized_status
      t.datetime :received_at, null: false
      t.string :source_ip
      t.jsonb :raw_payload, null: false, default: {}

      t.timestamps
    end

    add_index :portal_integration_events, [:portal, :received_at]
    add_index :portal_integration_events, [:portal, :habitation_code]
    add_index :portal_integration_events, [:portal, :external_listing_id]
  end
end
