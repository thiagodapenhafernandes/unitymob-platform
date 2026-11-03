class IndexImovelwebLeadIdentity < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    execute <<~SQL
      CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS index_leads_on_tenant_imovelweb_event
      ON leads (tenant_id, (other_information->>'imovelweb_event_id'))
      WHERE (other_information->>'imovelweb_event_id') IS NOT NULL
    SQL
  end

  def down
    execute "DROP INDEX CONCURRENTLY IF EXISTS index_leads_on_tenant_imovelweb_event"
  end
end
