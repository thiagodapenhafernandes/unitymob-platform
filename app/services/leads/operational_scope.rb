module Leads
  class OperationalScope
    ACTIVE_SQL = <<~SQL.squish.freeze
      leads.archived_at IS NULL
      AND NOT (COALESCE(leads.attribution_data #>> '{archive_details,archived}', 'false') IN ('true', '1', 't')
        AND COALESCE(leads.status, '') = :discarded)
      AND NOT EXISTS (
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

    def self.without_archived(scope, tenant:)
      scope.where(ACTIVE_SQL, tenant_id: tenant.id, discarded: Lead.status_value(:descartado, tenant: tenant))
    end

    def self.archived(scope, tenant:)
      scope.where.not([ACTIVE_SQL, {tenant_id: tenant.id, discarded: Lead.status_value(:descartado, tenant: tenant)}])
    end

    def self.visible_to(scope, user:, tenant:)
      return scope if user&.tenant_owner? && user.tenant_id == tenant.id

      without_archived(scope, tenant: tenant)
    end

    def self.favorites(scope, user:, tenant:)
      favorites = scope.joins(:lead_favorites).where(lead_favorites: {tenant_id: tenant.id, admin_user_id: user&.id})
      without_closed_mirrored(favorites, tenant: tenant)
    end

    def self.without_closed_mirrored(scope, tenant:)
      integration = tenant.external_lead_integration
      return scope unless integration&.mirror_c2s_owners?

      # O C2S preserva a estrela no histórico, mas exclui encerrados da aba.
      closed = tenant.leads.where(external_lead_integration_id: integration.id,
        status: Lead.non_operational_status_values(tenant: tenant))
      scope.where.not(id: closed.select(:id))
    end

    def self.unanswered_mirrored(scope, tenant:)
      integration = tenant.external_lead_integration
      return scope.none unless integration&.mirror_c2s_owners?

      scope.where(external_lead_integration_id: integration.id).where(<<~SQL.squish)
        EXISTS (
          SELECT 1 FROM jsonb_array_elements(
            CASE WHEN jsonb_typeof(leads.other_information #> '{external_lead_payload,messages}') = 'array'
              THEN leads.other_information #> '{external_lead_payload,messages}' ELSE '[]'::jsonb END
          ) AS message
          WHERE message ->> 'sender_type' = 'Customer'
            AND NULLIF(message ->> 'read_at', '') IS NULL
        )
      SQL
    end

    def self.mirrored(scope, tenant:)
      integration = tenant.external_lead_integration
      integration&.mirror_c2s_owners? ? scope.where(external_lead_integration_id: integration.id) : scope.none
    end

    def self.current_external_schedules(scope, tenant:)
      mirrored_ids = mirrored(tenant.leads, tenant: tenant).select(:id)
      local = scope.where.not(lead_id: mirrored_ids)
      current = scope.where(lead_id: mirrored_ids).joins(:lead).where(<<~SQL.squish)
        EXISTS (
          SELECT 1 FROM jsonb_array_elements(
            CASE WHEN jsonb_typeof(leads.other_information #> '{external_lead_payload,schedulated_actions}') = 'array'
              THEN leads.other_information #> '{external_lead_payload,schedulated_actions}'
              WHEN jsonb_typeof(leads.other_information #> '{external_lead_payload,attributes,schedulated_actions}') = 'array'
              THEN leads.other_information #> '{external_lead_payload,attributes,schedulated_actions}' ELSE '[]'::jsonb END
          ) AS action
          WHERE action = lead_activities.metadata -> 'raw'
        )
      SQL
      scope.where(id: local.select(:id)).or(scope.where(id: current.select('lead_activities.id')))
    end
  end
end
