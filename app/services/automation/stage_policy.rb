module Automation
  module StagePolicy
    DISTRIBUTION_OWNED_STAGES = [
      "Aguardando Aceite",
      "Represado"
    ].freeze

    module_function

    def allowed_transition_stages
      Lead.status_options.reject { |status| distribution_owned_stage?(status) }
    end

    def allowed_transition?(stage)
      stage = Lead.status_value(stage)
      stage.present? && allowed_transition_stages.map { |item| Lead.status_value(item) }.include?(stage)
    end

    def distribution_owned_stage?(stage)
      normalized = Lead.status_value(stage)
      DISTRIBUTION_OWNED_STAGES.any? { |item| Lead.status_value(item) == normalized }
    end

    def blocked_stage_message(stage)
      "etapa #{stage} pertence a Distribuicao de Leads; use automacao apenas para etapas de acompanhamento"
    end
  end
end
