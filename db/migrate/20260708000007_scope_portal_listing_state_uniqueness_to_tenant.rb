class ScopePortalListingStateUniquenessToTenant < ActiveRecord::Migration[7.1]
  # Os UNIQUE de portal_listing_states eram GLOBAIS (portal, habitation_code) e
  # (portal, external_listing_id). Como habitations.codigo/external_listing_id só
  # é único POR tenant, dois tenants no mesmo portal colidiam: o webhook do
  # tenant A montava um registro novo (lookup já escopado por tenant) e o save!
  # violava o índice global → RecordNotUnique 500 persistente. Escopa por tenant.
  def up
    return unless table_exists?(:portal_listing_states)
    return unless column_exists?(:portal_listing_states, :tenant_id)

    remove_index :portal_listing_states, name: "idx_portal_listing_states_portal_code", if_exists: true
    remove_index :portal_listing_states, name: "idx_portal_listing_states_portal_external", if_exists: true

    add_index :portal_listing_states, [:tenant_id, :portal, :habitation_code],
              unique: true, name: "idx_portal_listing_states_tenant_portal_code",
              if_not_exists: true
    add_index :portal_listing_states, [:tenant_id, :portal, :external_listing_id],
              unique: true, where: "external_listing_id IS NOT NULL",
              name: "idx_portal_listing_states_tenant_portal_external",
              if_not_exists: true
  end

  def down
    return unless table_exists?(:portal_listing_states)

    remove_index :portal_listing_states, name: "idx_portal_listing_states_tenant_portal_code", if_exists: true
    remove_index :portal_listing_states, name: "idx_portal_listing_states_tenant_portal_external", if_exists: true

    add_index :portal_listing_states, [:portal, :habitation_code],
              unique: true, name: "idx_portal_listing_states_portal_code", if_not_exists: true
    add_index :portal_listing_states, [:portal, :external_listing_id],
              unique: true, where: "external_listing_id IS NOT NULL",
              name: "idx_portal_listing_states_portal_external", if_not_exists: true
  end
end
