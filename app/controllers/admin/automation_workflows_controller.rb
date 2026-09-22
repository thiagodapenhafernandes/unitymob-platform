class Admin::AutomationWorkflowsController < Admin::BaseController
  requires_permission :manage, :automacoes
  before_action :set_workflow, only: [:show, :builder, :destroy, :save_draft, :publish, :simulate]
  before_action :set_catalogs, only: [:builder]

  # A listagem de fluxos vive no hub de automação; esta rota só existia como alvo de "Sair para listagem".
  def index
    redirect_to admin_automation_rules_path
  end

  def new
    # Só o nome. Gatilho, número e template são escolhidos no builder; o template só chega aqui vindo de um fluxo de resposta.
    @selected_template = template_choices.find { |template| template.id == params[:whatsapp_template_id].to_i }
    @workflow = current_tenant.automation_workflows.new(name: (@selected_template ? "Conversa: #{@selected_template.name}" : "Nova intervenção automatizada"))
    @page_title = "Nova intervenção automatizada"
  end

  def create
    @workflow = current_tenant.automation_workflows.new(workflow_params)
    @workflow.created_by = current_admin_user

    template = template_choices.find { |item| item.id == params[:whatsapp_template_id].to_i }
    if @workflow.save
      @workflow.versions.create!(
        version_number: 1,
        status: "draft",
        definition: template ? Automation::TemplateScaffold.call(template) : Automation::WorkflowDefinition.default_definition,
        created_by: current_admin_user
      )
      redirect_to builder_admin_automation_workflow_path(@workflow), notice: "Intervenção criada como rascunho."
    else
      @selected_template = template
      @page_title = "Nova intervenção automatizada"
      render :new, status: :unprocessable_entity
    end
  end

  def show
    redirect_to builder_admin_automation_workflow_path(@workflow)
  end

  def builder
    @version = @workflow.draft_version!
    consume_simulation_result
    set_monitoring
    @page_title = @workflow.name
  end

  def save_draft
    version = @workflow.draft_version!
    definition = parse_definition

    if persist_draft(version, definition)
      redirect_to builder_admin_automation_workflow_path(@workflow), notice: "Rascunho salvo."
    else
      set_catalogs
      set_monitoring
      @version = version
      @page_title = @workflow.name.presence || "Automação de acompanhamento"
      flash.now[:alert] = "Revise os campos destacados antes de salvar."
      render :builder, status: :unprocessable_entity
    end
  end

  def publish
    version = @workflow.draft_version!
    definition = mark_campaign_workflow_customized(parse_definition)
    version.assign_attributes(definition: definition)

    if @workflow.update(workflow_params) && version.save
      ActiveRecord::Base.transaction do
        @workflow.publish!(version: version, admin_user: current_admin_user)
        Automation::ReceptiveBinding.call(@workflow, entry_config(definition))
      end
      redirect_to builder_admin_automation_workflow_path(@workflow), notice: "Intervenção publicada e ativada."
    else
      set_catalogs
      set_monitoring
      @version = version
      @page_title = @workflow.name.presence || "Automação de acompanhamento"
      flash.now[:alert] = "A intervenção ainda não pode ser publicada."
      render :builder, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid, Automation::ReceptiveBinding::Error => e
    set_catalogs
    set_monitoring
    @version = version
    @page_title = @workflow.name.presence || "Automação de acompanhamento"
    flash.now[:alert] = e.is_a?(Automation::ReceptiveBinding::Error) ? e.message : "A intervenção ainda não pode ser publicada."
    render :builder, status: :unprocessable_entity
  end

  def simulate
    version = @workflow.draft_version!
    definition = parse_definition

    if persist_draft(version, definition)
      session[:automation_workflow_simulation_id] = @workflow.id
      redirect_to builder_admin_automation_workflow_path(@workflow),
                  notice: "Simulação gerada sem executar intervenções.",
                  status: :see_other
    else
      set_catalogs
      set_monitoring
      @version = version
      @page_title = @workflow.name.presence || "Automação de acompanhamento"
      flash.now[:alert] = "A simulação não pode ser gerada com a definição atual."
      render :builder, status: :unprocessable_entity
    end
  end

  def destroy
    @workflow.update!(status: "archived")
    redirect_to admin_automation_workflows_path, notice: "Intervenção arquivada."
  end

  private

  # Templates aprovados com botão de resposta rápida: dão o ponto de partida da conversa.
  def template_choices
    current_tenant.whatsapp_templates.approved.ordered.select { |template| template.interactive_buttons.any? { |button| button["actionable_reply"] } }
  end

  def entry_config(definition)
    entry = Array(definition.with_indifferent_access[:nodes]).find { |node| node[:type].to_s == "entry" }
    entry ? entry[:config].to_h : {}
  end

  def set_workflow
    @workflow = current_tenant.automation_workflows.find(params[:id])
  end

  def set_catalogs
    @trigger_options = AutomationRule::TRIGGERS
    @action_options = AutomationRule::WORKFLOW_ACTION_TYPES
    @status_options = Lead.status_options
    @automation_stage_options = Automation::StagePolicy.allowed_transition_stages
    @source_options = Lead.origin_options
    @broker_options = current_tenant.admin_users.active.order(:name).pluck(:name, :id)
    @template_options = current_tenant.whatsapp_templates.approved.ordered.pluck(:name, :name)
    @distribution_rule_options = current_tenant.distribution_rules.active.order(:name).pluck(:name, :id)
    set_whatsapp_start_catalog
  end

  # Início "clique em botão do WhatsApp": número -> templates daquele número (mesmo WABA) -> caminho por botão.
  def set_whatsapp_start_catalog
    @whatsapp_senders = current_tenant.whatsapp_sender_numbers.active.includes(:receptive_response_flow).ordered.map do |sender|
      { id: sender.id, label: sender.label, phone: sender.display_phone_number, waba_id: sender.waba_id,
        receptive_flow: sender.receptive_response_flow&.then { |flow| { id: flow.id, name: flow.name, workflow_id: flow.automation_workflow_id } } }
    end
    existing_flows = current_tenant.whatsapp_response_flows.index_by(&:whatsapp_template_id)
    @whatsapp_flow_templates = template_choices.map do |template|
      flow = existing_flows[template.id]
      { id: template.id, name: template.name, waba_id: template.waba_id,
        existing_flow: flow && { id: flow.id, name: flow.name, workflow_id: flow.automation_workflow_id },
        receptive_ok: %w[response_flow attendance].include?(template.usage_context.to_s),
        scaffold: Automation::TemplateScaffold.call(template) }
    end
  end

  def set_monitoring
    executions = @workflow.executions.includes(:lead, :automation_event, :automation_workflow_version, :steps).recent
    @recent_executions = executions.limit(12)
    @execution_counts = @workflow.executions.group(:status).count
    @waiting_steps = AutomationExecutionStep
      .joins(:automation_execution)
      .where(automation_executions: { automation_workflow_id: @workflow.id })
      .where(status: "waiting")
      .where.not(scheduled_for: nil)
      .includes(automation_execution: :lead)
      .order(:scheduled_for)
      .limit(8)
    @failed_executions = executions.where(status: "failed").limit(6)
  end

  def workflow_params
    params.fetch(:automation_workflow, {}).permit(:name, :definition_json).slice(:name)
  end

  def persist_draft(version, definition)
    definition = mark_campaign_workflow_customized(definition)
    @workflow.assign_attributes(workflow_params) if params[:automation_workflow].present?
    version.assign_attributes(definition: definition, created_by: version.created_by || current_admin_user)

    return false unless @workflow.valid? && version.valid?

    @workflow.save!
    version.save!
    true
  end

  def consume_simulation_result
    return unless session.delete(:automation_workflow_simulation_id).to_i == @workflow.id

    @simulation_result = Automation::Simulator.workflow(@version.definition_hash)
  end

  def parse_definition
    raw = params.dig(:automation_workflow, :definition_json).to_s
    return Automation::WorkflowDefinition.default_definition if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

  def mark_campaign_workflow_customized(definition)
    return definition unless @workflow.whatsapp_campaign_source?
    return definition if params.dig(:automation_workflow, :definition_json).blank?

    normalized = definition.deep_dup.with_indifferent_access
    source = (normalized[:source].is_a?(Hash) ? normalized[:source] : {}).with_indifferent_access
    return definition unless source[:kind].to_s == "whatsapp_campaign"

    source[:managed_by_campaign] = false
    source[:customized_by_advanced_user] = true
    source[:customized_by_admin_user_id] = current_admin_user&.id
    source[:customized_at] = Time.current.iso8601
    source[:sync_mode] = "advanced_custom"
    normalized[:source] = source
    normalized.to_h.deep_stringify_keys
  end
end
