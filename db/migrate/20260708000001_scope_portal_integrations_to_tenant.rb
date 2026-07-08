class ScopePortalIntegrationsToTenant < ActiveRecord::Migration[7.1]
  # portal_integrations era GLOBAL: uma conta configurando um portal (ex.: OLX,
  # ZAP) valia para TODAS — vazamento cross-tenant do feed/webhook. Passa a ser
  # POR TENANT: adiciona tenant_id, faz backfill para o tenant primário (menor
  # id em tenants) e troca o UNIQUE global em (portal) por UNIQUE (tenant_id,
  # portal). O UNIQUE global em feed_token é PRESERVADO — é a chave de lookup
  # público do feed (rota sem sessão), então deve permanecer única no sistema.
  def up
    unless column_exists?(:portal_integrations, :tenant_id)
      add_reference :portal_integrations, :tenant, foreign_key: true, index: true
    end

    # Backfill: toda linha existente vai para o tenant primário (menor id).
    first_tenant_id = select_value("SELECT id FROM tenants ORDER BY id LIMIT 1")
    if first_tenant_id.present?
      execute <<~SQL
        UPDATE portal_integrations SET tenant_id = #{first_tenant_id.to_i}
         WHERE tenant_id IS NULL
      SQL
    end

    # Troca UNIQUE global em (portal) por UNIQUE (tenant_id, portal).
    if index_exists?(:portal_integrations, :portal, name: :index_portal_integrations_on_portal)
      remove_index :portal_integrations, name: :index_portal_integrations_on_portal
    end
    unless index_exists?(:portal_integrations, [:tenant_id, :portal], name: :idx_portal_integrations_on_tenant_and_portal)
      add_index :portal_integrations, [:tenant_id, :portal], unique: true,
                name: :idx_portal_integrations_on_tenant_and_portal
    end
    # feed_token: mantém unicidade GLOBAL (chave pública de lookup do feed).
  end

  def down
    if index_exists?(:portal_integrations, [:tenant_id, :portal], name: :idx_portal_integrations_on_tenant_and_portal)
      remove_index :portal_integrations, name: :idx_portal_integrations_on_tenant_and_portal
    end
    unless index_exists?(:portal_integrations, :portal, name: :index_portal_integrations_on_portal)
      add_index :portal_integrations, :portal, unique: true,
                name: :index_portal_integrations_on_portal
    end
    remove_reference :portal_integrations, :tenant, foreign_key: true if column_exists?(:portal_integrations, :tenant_id)
  end
end
