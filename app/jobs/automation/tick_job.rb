module Automation
  # Varre regras baseadas em tempo (lead parado) e dispara as que casam.
  # Roda periodicamente via config/recurring.yml.
  class TickJob < ApplicationJob
    queue_as :default

    def perform
      AutomationRule.time_based.ordered.find_each do |rule|
        Current.set(tenant: rule.tenant) do
          hours = rule.idle_hours
          next if hours <= 0

          scope = Automation::LeadCandidates.for(rule.tenant, rule.conditions_hash, trigger: "lead_idle")
          scope = scope.where.not(id: rule.tenant.automation_events.where(name: "lead_idle", source: "automation_tick")
            .where("payload ->> 'automation_rule_id' = ?", rule.id.to_s).where.not(lead_id: nil).select(:lead_id))

          # Dedup: não reprocessar leads que esta regra já tocou — anti-join no
          # banco (NOT EXISTS) em vez de materializar todos os ids em memória;
          # runs com lead_id nulo ficam de fora naturalmente.
          scope = scope.where(
            "NOT EXISTS (SELECT 1 FROM automation_runs " \
            "WHERE automation_runs.automation_rule_id = ? " \
            "AND automation_runs.lead_id = leads.id)",
            rule.id
          )

          scope.limit(200).find_each do |lead|
            Automation::Dispatcher.dispatch(
              :lead_idle,
              lead,
              source: "automation_tick",
              payload: { automation_rule_id: rule.id, idle_hours: hours },
              idempotency_key: "lead_idle:rule:#{rule.id}:lead:#{lead.id}"
            )
          end
        end
      end

      Automation::WorkflowDispatcher.dispatch_idle_candidates
      Automation::WorkflowDispatcher.dispatch_scheduled_routines
    end
  end
end
