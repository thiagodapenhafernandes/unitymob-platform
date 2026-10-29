module Leads
  # O histórico continua disponível quando o operador filtra status ou motivo.
  class OperationalScope
    def self.without_archived(scope, tenant:)
      scope.where(archived_at: nil).where(<<~SQL.squish, tenant_id: tenant.id, discarded: Lead.status_value(:descartado, tenant: tenant))
        NOT (COALESCE(leads.attribution_data #>> '{archive_details,archived}', 'false') IN ('true', '1', 't')
          AND COALESCE(leads.status, '') = :discarded)
        AND
        NOT EXISTS (
          SELECT 1 FROM lead_pipeline_stages archived_stage
          WHERE archived_stage.tenant_id = :tenant_id
            AND archived_stage.tenant_id = leads.tenant_id
            AND archived_stage.stage_type = 'archived'
            AND (archived_stage.id = leads.lead_pipeline_stage_id
              OR (leads.lead_pipeline_stage_id IS NULL
                AND archived_stage.lead_pipeline_id = leads.lead_pipeline_id
                AND archived_stage.name = leads.status))
        )
      SQL
    end
  end
end
