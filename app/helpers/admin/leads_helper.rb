module Admin::LeadsHelper
  def lead_business_pipeline_data(lead)
    pipelines = current_tenant.lead_pipelines.active.ordered.includes(stages: :policy).to_a
    {
      controller: "lead-pipeline-stage-select",
      lead_pipeline_stage_select_require_choice_value: lead.persisted?,
      lead_pipeline_stage_select_business_pipelines_value: Lead::BUSINESS_TYPES.keys.to_h { |type|
        [type, LeadPipeline.for_business_type(tenant: current_tenant, business_type: type)&.id]
      },
      lead_pipeline_stage_select_stages_value: pipelines.to_h { |pipeline|
        stages = pipeline.stages.select(&:active?).sort_by { |stage| [stage.position || Float::INFINITY, stage.id] }
        [pipeline.id, visible_stages_for(stages).map { |stage| { id: stage.id, name: stage.name } }]
      }
    }
  end

  def lead_navigation_tabs(mobile: false)
    tabs = [
      ["todo", "A fazer", "house-door", "Tarefas vencidas ou sem data, e leads novos sem primeiro contato."],
      ["visits", "Visitas", "bullseye", "Leads com visita marcada, mesmo se a data já passou, até ser resolvida."],
      ["future", "Futuras", "clock", "Leads com retorno ou tarefa marcada para acompanhar depois."],
      ["favorites", "Favoritos", "star", "Leads que você marcou para acompanhar mais de perto."]
    ]
    tabs << ["verify", "A verificar", "shield-check", "Apurações de compartilhamento aguardando verificação de identidade."] unless mobile
    tabs << ["all", "Todos", "archive", "Todos os leads que aparecem para você nesta tela."]
    if tenant_owner?
      tabs << ["archived", "Arquivados", "archive-fill", "Histórico exclusivo do administrador da conta. Preserva o corretor responsável e quem arquivou."]
    end
    tabs
  end

  def stage_conversion_integration_state(provider)
    @stage_conversion_integration_states ||= {}
    @stage_conversion_integration_states[provider] ||= Integrations::StageConversionAvailability.new(current_tenant).state(provider)
  end

  def lead_contact_kind_label(activity)
    LeadActivity::CONTACT_KIND_LABELS[activity.meta("contact_kind").to_s] || "Anotação interna"
  end

  def lead_contact_result_label(activity)
    LeadActivity::CONTACT_RESULT_LABELS[activity.meta("contact_result").to_s]
  end

  def lead_unsuccessful_attempt_count(lead)
    lead&.unsuccessful_attempt_count || 0
  end
end
