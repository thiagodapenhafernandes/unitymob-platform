module Leads
  class OperationalPipelineTemplate
    ARCHIVE_REASON_NAMES = [
      "Alugado",
      "Apenas pesquisando",
      "Avaliação baixa na troca",
      "Cliente não respondeu",
      "Compra adiada",
      "Contato Inválido",
      "Corretor Parceiro",
      "Falta de produto",
      "Fechou negócio em outro lugar",
      "Ficha recusada",
      "Já foi vendido",
      "Lead duplicado",
      "Localização não agradou",
      "Não consegui contatar",
      "Não possui renda",
      "Preço alto",
      "Produto não agradou",
      "Proposta do cliente com valor baixo",
      "Proposta inviável",
      "Tratada com qualificação",
      "Tratada sem qualificação",
      "Vendedor pesquisando produto"
    ].freeze

    TRANSITIONS = {
      "Novo Lead" => ["Em Atendimento"],
      "Em Atendimento" => ["Visita/Contato", "Proposta", "Perdido", "Arquivado"],
      "Visita/Contato" => ["Em Atendimento", "Proposta", "Perdido", "Arquivado"],
      "Proposta" => ["Em Atendimento", "Ganho", "Perdido", "Arquivado"],
      "Ganho" => ["Arquivado"],
      "Perdido" => ["Em Atendimento", "Arquivado"],
      "Arquivado" => ["Em Atendimento"]
    }.freeze

    POLICY_DEFINITIONS = {
      "Novo Lead" => { future_activity_limit_days: 2, qualification_enabled: true },
      "Em Atendimento" => { future_activity_limit_days: 7, qualification_enabled: true },
      "Visita/Contato" => { future_activity_limit_days: 15, qualification_enabled: true },
      "Proposta" => { future_activity_limit_days: 10, qualification_enabled: true },
      "Ganho" => { visible_to_roles: %w[manager admin], qualification_enabled: false },
      "Perdido" => { divergence_queue_enabled: true, qualification_enabled: true },
      "Arquivado" => { visible_to_roles: %w[manager administrative admin], qualification_enabled: false }
    }.freeze

    AUTOMATION_DEFINITIONS = [
      {
        stage: "Novo Lead",
        trigger: "stage_duration",
        action_type: "create_task",
        action_config: {
          "task_title" => "Primeiro atendimento do lead",
          "due_in_days" => 1,
          "note" => "Lead novo aguardando primeiro atendimento."
        }
      },
      {
        stage: "Em Atendimento",
        trigger: "customer_inactivity",
        action_type: "create_task",
        action_config: {
          "task_title" => "Retomar contato com o lead",
          "due_in_days" => 1,
          "note" => "Lead sem interação recente do cliente."
        }
      },
      {
        stage: "Visita/Contato",
        trigger: "no_stage_change",
        action_type: "create_task",
        action_config: {
          "task_title" => "Atualizar retorno da visita ou contato",
          "due_in_days" => 1,
          "note" => "Atualize o resultado da visita ou do contato."
        }
      },
      {
        stage: "Proposta",
        trigger: "general_inactivity",
        action_type: "add_note",
        action_config: {
          "note" => "Proposta sem movimentação dentro do prazo configurado."
        }
      },
      {
        stage: "Perdido",
        trigger: "stage_duration",
        action_type: "archive_lead",
        action_config: {
          "note" => "Arquivado automaticamente após permanência em Perdido."
        }
      }
    ].freeze

    VALIDATION_CHAIN = [
      ["Novo Lead", "Em Atendimento"],
      ["Em Atendimento", "Visita/Contato"],
      ["Visita/Contato", "Proposta"],
      ["Proposta", "Ganho"],
      ["Ganho", "Perdido"],
      ["Perdido", "Arquivado"]
    ].freeze

    def self.apply!(...)
      new(...).apply!
    end

    def initialize(
      tenant:,
      pipeline: nil,
      automation_active: false,
      automation_after_amount: 1,
      automation_after_unit: "days",
      validation_chain: false
    )
      @tenant = tenant
      @pipeline = pipeline
      @automation_active = automation_active
      @automation_after_amount = automation_after_amount
      @automation_after_unit = automation_after_unit
      @validation_chain = validation_chain
    end

    def apply!
      raise ArgumentError, "Tenant obrigatório para aplicar template de funil" if tenant.blank?

      LeadPipeline.transaction do
        ensure_archive_reasons!
        ensure_pipeline!
        ensure_stages!
        ensure_policies!
        ensure_transitions!
        ensure_automations!
        pipeline
      end
    end

    private

    attr_reader :tenant, :automation_active, :automation_after_amount, :automation_after_unit, :validation_chain
    attr_accessor :pipeline

    def ensure_archive_reasons!
      existing_by_key = tenant.attribute_options
        .for_context("lead")
        .for_category("archive_reason")
        .to_a
        .index_by { |option| AttributeOption.normalized_name_key(option.name) }

      ARCHIVE_REASON_NAMES.each_with_index do |name, index|
        option = existing_by_key[AttributeOption.normalized_name_key(name)]
        option ||= tenant.attribute_options.new(context: "lead", category: "archive_reason", name: name)
        option.position = index if option.new_record? || option.position.blank?
        option.save! if option.new_record? || option.changed?
      end
    end

    def ensure_pipeline!
      self.pipeline ||= LeadPipeline.default_for(tenant:) || tenant.lead_pipelines.find_by(name: "Principal")
      self.pipeline ||= tenant.lead_pipelines.create!(
        name: "Principal",
        kind: "mixed",
        default_general: true,
        default_for_sale: true,
        default_for_rental: true,
        position: 0
      )
    end

    def ensure_stages!
      LeadPipeline::DEFAULT_STAGE_DEFINITIONS.each_with_index do |definition, index|
        stage = pipeline.stages.find_or_initialize_by(tenant: tenant, name: definition.fetch(:name))
        stage.assign_attributes(
          stage_type: definition.fetch(:stage_type),
          color: definition.fetch(:color),
          position: index,
          active: true
        )
        stage.save! if stage.new_record? || stage.changed?
      end
    end

    def ensure_policies!
      archive_reason_ids = archive_reasons.pluck(:id)
      stages_by_name.each_value do |stage|
        policy = stage.policy || stage.build_policy(tenant: tenant)
        policy.assign_attributes(
          LeadPipelineStagePolicy.default_attributes.merge(
            POLICY_DEFINITIONS.fetch(stage.name, {}),
            tenant: tenant,
            allowed_archive_reason_ids: archive_reason_ids
          )
        )
        policy.save! if policy.new_record? || policy.changed?
      end
    end

    def ensure_transitions!
      TRANSITIONS.each_with_index do |(stage_name, next_stage_names), stage_index|
        stage = stages_by_name.fetch(stage_name)
        next_stage_names.each_with_index do |next_stage_name, next_index|
          next_stage = stages_by_name.fetch(next_stage_name)
          transition = stage.transitions.find_or_initialize_by(tenant: tenant, next_stage: next_stage)
          transition.position = (stage_index * 10) + next_index
          transition.save! if transition.new_record? || transition.changed?
        end
      end
    end

    def ensure_automations!
      definitions = validation_chain ? validation_automation_definitions : AUTOMATION_DEFINITIONS
      definitions.each_with_index do |definition, index|
        stage = stages_by_name.fetch(definition.fetch(:stage))
        automation = stage.automations.find_or_initialize_by(
          tenant: tenant,
          position: index,
          trigger: definition.fetch(:trigger),
          action_type: definition.fetch(:action_type)
        )
        automation.assign_attributes(
          after_amount: automation_after_amount,
          after_unit: automation_after_unit,
          active: automation_active,
          auto_advance_to_stage: destination_stage_for(definition),
          action_config: action_config_for(definition)
        )
        automation.save! if automation.new_record? || automation.changed?
      end
    end

    def validation_automation_definitions
      VALIDATION_CHAIN.map do |stage_name, next_stage_name|
        {
          stage: stage_name,
          trigger: "stage_duration",
          action_type: "move_stage",
          auto_advance_to_stage: next_stage_name,
          action_config: {}
        }
      end
    end

    def destination_stage_for(definition)
      next_stage_name = definition[:auto_advance_to_stage]
      return unless next_stage_name.present?

      stages_by_name.fetch(next_stage_name)
    end

    def action_config_for(definition)
      config = definition.fetch(:action_config, {}).dup
      if definition.fetch(:action_type) == "archive_lead"
        reason = archive_reasons.find { |option| option.name == "Cliente não respondeu" } || archive_reasons.first
        config["archive_reason_id"] ||= reason&.id&.to_s
      end
      config
    end

    def stages_by_name
      @stages_by_name ||= pipeline.stages.reload.index_by(&:name)
    end

    def archive_reasons
      @archive_reasons ||= tenant.attribute_options.for_context("lead").for_category("archive_reason").ordered.to_a
    end
  end
end
