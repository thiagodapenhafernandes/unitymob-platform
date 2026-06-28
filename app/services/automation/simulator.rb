module Automation
  class Simulator
    SAMPLE_LIMIT = 8

    Result = Struct.new(:title, :summary, :candidate_count, :sample_leads, :actions, :warnings, keyword_init: true)

    def self.workflow(definition)
      new(definition: definition).workflow
    end

    def self.rule(trigger_event:, conditions:, actions:)
      new(trigger_event: trigger_event, conditions: conditions, actions: actions).rule
    end

    def initialize(definition: nil, trigger_event: nil, conditions: {}, actions: [])
      @definition = definition.is_a?(Hash) ? definition.with_indifferent_access : {}
      @trigger_event = trigger_event.to_s
      @conditions = conditions.is_a?(Hash) ? conditions.with_indifferent_access : {}
      @actions = Array(actions).map { |action| action.is_a?(Hash) ? action.with_indifferent_access : {} }
    end

    def workflow
      nodes = Array(@definition[:nodes]).map { |node| node.is_a?(Hash) ? node.with_indifferent_access : {} }
      entry = nodes.find { |node| node[:type].to_s == "entry" } || {}
      entry_config = entry[:config].is_a?(Hash) ? entry[:config].with_indifferent_access : {}
      conditions = nodes.select { |node| node[:type].to_s == "condition" }.map { |node| node[:config].is_a?(Hash) ? node[:config].with_indifferent_access : {} }
      actions = nodes.select { |node| node[:type].to_s == "action" }.map { |node| Automation::WorkflowActionAdapter.to_action(node) }
      waits = nodes.select { |node| %w[wait await_event await_whatsapp_response response_condition response_fallback].include?(node[:type].to_s) }

      build_result(
        title: "Simulação do builder",
        trigger_event: entry_config[:trigger],
        entry_policy: entry_config[:entry_policy],
        conditions: merge_conditions([entry_config] + conditions),
        actions: actions,
        waits: waits
      )
    end

    def rule
      build_result(
        title: "Simulação da regra",
        trigger_event: @trigger_event,
        entry_policy: "existing_and_future",
        conditions: @conditions,
        actions: @actions,
        waits: []
      )
    end

    private

    def build_result(title:, trigger_event:, entry_policy:, conditions:, actions:, waits:)
      scope = lead_scope(trigger_event, conditions)
      candidate_count = scope.count
      sample_leads = scope.limit(SAMPLE_LIMIT).to_a
      action_labels = actions.map { |action| Automation::ActionExecutor.label(action) }.presence || ["Nenhuma intervenção configurada"]

      Result.new(
        title: title,
        summary: summary_for(trigger_event, entry_policy, candidate_count),
        candidate_count: candidate_count,
        sample_leads: sample_leads,
        actions: action_labels + waits.map { |node| wait_label(node) },
        warnings: warnings_for(trigger_event, entry_policy, actions)
      )
    end

    def lead_scope(trigger_event, conditions)
      scope = Lead.all.order(updated_at: :desc)

      stage = conditions[:stage].presence
      stage ||= conditions[:to_stage].presence if trigger_event.to_s == "lead_stage_changed"
      scope = scope.where(status: Lead.status_value(stage)) if stage.present?

      source = conditions[:source].presence
      scope = scope.where("origin ILIKE ?", source) if source.present?

      idle_hours = conditions[:idle_hours].to_i
      if trigger_event.to_s == "lead_idle" && idle_hours.positive?
        scope = scope.where("leads.updated_at <= ?", idle_hours.hours.ago)
      end

      scope
    end

    def merge_conditions(conditions)
      conditions.each_with_object({}.with_indifferent_access) do |config, merged|
        merged[:stage] ||= config[:stage].presence
        merged[:from_stage] ||= config[:from_stage].presence
        merged[:to_stage] ||= config[:to_stage].presence
        merged[:source] ||= config[:source].presence
        merged[:idle_hours] ||= config[:idle_hours].presence
        merged[:message_contains] ||= config[:message_contains].presence
        merged[:message_not_contains] ||= config[:message_not_contains].presence
      end
    end

    def warnings_for(trigger_event, entry_policy, actions)
      warnings = []
      warnings << "Esta simulação não executa tarefas, mensagens, notas nem mudanças de etapa."
      warnings << "Entrada configurada para eventos futuros: leads atuais aparecem apenas como referência." if entry_policy.to_s == "future"
      warnings << "Lead parado depende da rotina periódica da automação." if trigger_event.to_s == "lead_idle"
      warnings << "Rotina agendada depende do monitor periódico da automação." if trigger_event.to_s == "scheduled_routine"
      warnings << "Na simulação de mudança de etapa, a etapa anterior é apenas referência; no evento real ela será validada pelo histórico da mudança." if trigger_event.to_s == "lead_stage_changed"
      if trigger_event.to_s == "whatsapp_received"
        warnings << "Filtros de texto do WhatsApp são validados no evento real da mensagem; a simulação mostra apenas leads compatíveis com etapa/origem."
      end
      warnings.concat(conflict_warnings(trigger_event))

      actions.each do |action|
        next unless action[:type].to_s == "move_stage"

        to = action[:to].to_s
        warnings << Automation::StagePolicy.blocked_stage_message(to) unless Automation::StagePolicy.allowed_transition?(to)
      end

      warnings.uniq
    end

    def conflict_warnings(trigger_event)
      trigger_event = trigger_event.to_s
      return [] if trigger_event.blank?

      rule_count = AutomationRule.for_event(trigger_event).count
      workflow_count = Automation::WorkflowDispatcher.active_workflows_for_event(trigger_event).count
      total = rule_count + workflow_count
      return [] if total.zero?

      ["Ja existem #{total} automacao(oes) ativa(s) observando #{Automation::EventCatalog.label(trigger_event)}; revise conflitos antes de ativar."]
    end

    def summary_for(trigger_event, entry_policy, candidate_count)
      trigger = Automation::EventCatalog.label(trigger_event)
      policy = entry_policy.to_s == "future" ? "novos eventos" : "base atual e novos eventos"
      "#{trigger}: #{candidate_count} lead(s) atuais encontrados para #{policy}."
    end

    def wait_label(node)
      config = node[:config].is_a?(Hash) ? node[:config].with_indifferent_access : {}
      if node[:type].to_s == "await_event"
        amount = config[:timeout_amount].presence || 1
        unit = { "minutes" => "minuto(s)", "hours" => "hora(s)", "days" => "dia(s)" }[config[:timeout_unit].to_s] || "dia(s)"
        return "aguardar #{Automation::EventCatalog.label(config[:trigger])} por ate #{amount} #{unit}"
      end
      if node[:type].to_s == "await_whatsapp_response"
        amount = config[:timeout_amount].presence || 1
        unit = { "minutes" => "minuto(s)", "hours" => "hora(s)", "days" => "dia(s)" }[config[:timeout_unit].to_s] || "dia(s)"
        return "aguardar resposta WhatsApp por ate #{amount} #{unit}"
      end
      if node[:type].to_s == "response_condition"
        return "condicao de resposta: #{config[:field].presence || 'campo'} #{config[:operator].presence || 'equals'} #{config[:value]}"
      end
      if node[:type].to_s == "response_fallback"
        return config[:fallback_type].to_s == "timeout" ? "fallback: sem resposta ate timeout" : "fallback: resposta nao reconhecida"
      end

      return "esperar ate #{config[:run_at]}" if config[:mode].to_s == "datetime" && config[:run_at].present?
      return "esperar proxima janela comercial" if config[:mode].to_s == "next_business_window"

      amount = config[:amount].presence || 1
      unit = { "minutes" => "minuto(s)", "hours" => "hora(s)", "days" => "dia(s)" }[config[:unit].to_s] || "dia(s)"
      suffix = config[:mode].to_s == "business_duration" ? " em horario comercial" : ""
      "esperar #{amount} #{unit}#{suffix}"
    end
  end
end
