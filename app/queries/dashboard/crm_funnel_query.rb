module Dashboard
  class CrmFunnelQuery
    def initialize(scope:, tenant:, starts_at:, ends_at:, now: Time.current)
      @tenant = tenant
      @scope = scope.where(tenant_id: tenant.id).where(leads: { created_at: starts_at..ends_at }).reorder(nil)
      @now = now
    end

    def call
      ids = @scope.select(:id)
      qualified = @scope.where("broker_qualification_status = 'qualified' OR manager_qualification_status = 'qualified'")
      assessed = @scope.where("COALESCE(broker_qualification_status, '') <> '' OR COALESCE(manager_qualification_status, '') <> ''")
      visits = Appointment.where(tenant_id: @tenant.id, lead_id: ids, kind: "visita")
      completed = visits.where(status: "realizado")
      proposals = Proposal.where(lead_id: ids)
      sent = proposals.where.not(sent_at: nil)
      won = @scope.won_in_crm(tenant: @tenant)
      counts = {
        leads: @scope.count, qualified: qualified.count,
        visited: completed.distinct.count(:lead_id), proposed: sent.distinct.count(:lead_id), won: won.count
      }
      {
        counts: counts, captured_at: @now,
        gaps: {
          unassessed: counts[:leads] - assessed.count,
          overdue_visits: visits.where(status: "agendado").where("starts_at < ?", @now).count,
          visited_without_qualification: @scope.where(id: completed.select(:lead_id)).where.not(id: qualified.select(:id)).count,
          missing_channel: @scope.where("NULLIF(TRIM(attribution_channel), '') IS NULL").count,
          missing_stage: @scope.where(lead_pipeline_stage_id: nil).count
        },
        completed_visits: completed.count, draft_proposals: proposals.where(status: "rascunho").count,
        legacy_wins: won.where.not(id: @scope.joins(:lead_pipeline_stage).where(lead_pipeline_stages: { stage_type: "won" }).select(:id)).count,
        eligible: @scope.where("attribution_data->>'analytics_consent' = 'granted' AND attribution_data->>'client_id' ~ '^[0-9]{1,20}\\.[0-9]{1,20}$'").count
      }
    end
  end
end
