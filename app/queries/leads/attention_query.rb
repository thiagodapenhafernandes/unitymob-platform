module Leads
  class AttentionQuery
    def initialize(scope:, sla_hours:, contact_kinds:, now: Time.current)
      @scope = scope
      @sla_hours = sla_hours
      @contact_kinds = contact_kinds
      @now = now
    end

    def call
      @scope.where([
        <<~SQL.squish,
          leads.status = ?
          OR leads.admin_user_id IS NULL
          OR EXISTS (
            SELECT 1
            FROM tasks attention_tasks
            WHERE attention_tasks.tenant_id = leads.tenant_id
              AND attention_tasks.lead_id = leads.id
              AND attention_tasks.status = 'pendente'
              AND attention_tasks.due_at IS NOT NULL
              AND attention_tasks.due_at < ?
          )
          OR (
            leads.created_at < ?
            AND NOT EXISTS (
              SELECT 1
              FROM lead_activities contact_activities
              WHERE contact_activities.lead_id = leads.id
                AND contact_activities.kind IN (?)
            )
          )
        SQL
        Lead.status_value(:represado),
        @now,
        @now - @sla_hours.hours,
        @contact_kinds
      ])
    end
  end
end
