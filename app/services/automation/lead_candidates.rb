module Automation
  # Mesmo recorte de entrada para a varredura, base atual e simulação.
  class LeadCandidates
    def self.for(tenant, config, trigger: nil)
      config = config.with_indifferent_access
      scope = tenant.leads
      scope = scope.where(status: Lead.status_value(config[:stage])) if config[:stage].present?
      scope = scope.where("LOWER(origin) = ?", config[:source].to_s.downcase) if config[:source].present?
      ids = Automation::WorkflowDispatcher.distribution_rule_ids_for(config)
      scope = scope.where(distribution_rule_id: ids) if ids.any?
      if trigger.to_s == "lead_idle"
        return scope.none unless config[:idle_hours].to_i.positive?
        scope = scope.where("leads.updated_at <= ?", config[:idle_hours].to_i.hours.ago)
      end
      scope
    end
  end
end
