class AddTenantToPortalListingStatesAndEvents < ActiveRecord::Migration[7.1]
  # Tabelas satélite do portal (estado por anúncio + eventos de webhook) passam
  # a carregar tenant_id explícito para o escopo funcionar sem inferência frágil.
  # Sem FK rígida (bigint puro): são tabelas de alto volume/append-only e a
  # derivação de tenant é best-effort. Backfill: deriva do portal_integration
  # correspondente (join por `portal`, que após a migration 0001 já é único por
  # tenant); na ausência de match, cai no tenant primário (menor id).
  def up
    unless column_exists?(:portal_listing_states, :tenant_id)
      add_column :portal_listing_states, :tenant_id, :bigint
      add_index  :portal_listing_states, :tenant_id
    end

    unless column_exists?(:portal_integration_events, :tenant_id)
      add_column :portal_integration_events, :tenant_id, :bigint
      add_index  :portal_integration_events, :tenant_id
    end

    first_tenant_id = select_value("SELECT id FROM tenants ORDER BY id LIMIT 1")

    # 1) Deriva do portal_integration (join por portal).
    execute <<~SQL
      UPDATE portal_listing_states pls
         SET tenant_id = pi.tenant_id
        FROM portal_integrations pi
       WHERE pls.tenant_id IS NULL
         AND pi.tenant_id IS NOT NULL
         AND pi.portal = pls.portal
    SQL
    execute <<~SQL
      UPDATE portal_integration_events pie
         SET tenant_id = pi.tenant_id
        FROM portal_integrations pi
       WHERE pie.tenant_id IS NULL
         AND pi.tenant_id IS NOT NULL
         AND pi.portal = pie.portal
    SQL

    # 2) Fallback: sem portal_integration correspondente → tenant primário.
    if first_tenant_id.present?
      execute "UPDATE portal_listing_states     SET tenant_id = #{first_tenant_id.to_i} WHERE tenant_id IS NULL"
      execute "UPDATE portal_integration_events SET tenant_id = #{first_tenant_id.to_i} WHERE tenant_id IS NULL"
    end
  end

  def down
    if column_exists?(:portal_integration_events, :tenant_id)
      remove_index  :portal_integration_events, :tenant_id if index_exists?(:portal_integration_events, :tenant_id)
      remove_column :portal_integration_events, :tenant_id
    end
    if column_exists?(:portal_listing_states, :tenant_id)
      remove_index  :portal_listing_states, :tenant_id if index_exists?(:portal_listing_states, :tenant_id)
      remove_column :portal_listing_states, :tenant_id
    end
  end
end
