class AddPortalLeadsToPortalIntegrations < ActiveRecord::Migration[7.1]
  # Idempotência dos leads vindos dos portais (o Grupo OLX reentrega o mesmo
  # lead até 3x): unique parcial em (tenant_id,
  # other_information->>'portal_lead_id'), a MESMA expressão da query de
  # dedupe do PortalLeadProcessingJob. Chave nova: sem duplicatas a neutralizar.
  INDEX_NAME = "index_leads_on_tenant_portal_lead_id".freeze

  def up
    add_column :portal_integrations, :leads_enabled, :boolean, default: false, null: false
    add_column :portal_integrations, :last_lead_at, :datetime

    execute <<~SQL
      CREATE UNIQUE INDEX IF NOT EXISTS #{INDEX_NAME}
      ON leads (tenant_id, (other_information->>'portal_lead_id'))
      WHERE (other_information->>'portal_lead_id') IS NOT NULL
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS #{INDEX_NAME}"
    remove_column :portal_integrations, :last_lead_at
    remove_column :portal_integrations, :leads_enabled
  end
end
