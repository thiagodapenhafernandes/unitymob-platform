class CreatePortalListingStates < ActiveRecord::Migration[7.1]
  def change
    create_table :portal_listing_states do |t|
      t.string :portal, null: false
      t.references :habitation, null: true, foreign_key: true
      t.string :habitation_code
      t.string :external_listing_id
      t.string :last_event_type, null: false
      t.string :last_status
      t.datetime :last_received_at, null: false
      t.jsonb :last_payload, null: false, default: {}

      t.timestamps
    end

    add_index :portal_listing_states, [:portal, :habitation_code], unique: true, name: "idx_portal_listing_states_portal_code"
    add_index :portal_listing_states, [:portal, :external_listing_id], unique: true, where: "external_listing_id IS NOT NULL", name: "idx_portal_listing_states_portal_external"
  end
end
