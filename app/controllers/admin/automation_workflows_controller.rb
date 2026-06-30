class Admin::AutomationWorkflowsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :automacoes) }
  before_action :set_workflow, only: [:show, :builder, :destroy, :save_draft, :publish, :simulate]
  before_action :set_catalogs, only: [:new, :builder]

  def index
    @workflows = current_tenant.automation_workflows.includes(:active_version).recent
    @page_title = "Automação de acompanhamento"
  end

  def new
    @workflow = current_tenant.automation_workflows.new(name: "Nova intervenção automatizada")
    @page_title = "Nova intervenção automatizada"
  end

  def create
    @workflow = current_tenant.automation_workflows.new(workflow_params)
    @workflow.created_by = current_admin_user

    if @workflow.save
      @workflow.versions.create!(
        version_number: 1,
        status: "draft",
        definition: Automation::WorkflowDefinition.default_definition,
        created_by: current_admin_user
      )
      redirect_to builder_admin_automation_workflow_path(@workflow), notice: "Intervenção criada como rascunho."
    else
      set_catalogs
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
      @workflow.publish!(version: version, admin_user: current_admin_user)
      redirect_to builder_admin_automation_workflow_path(@workflow), notice: "Intervenção publicada e ativada."
    else
      set_catalogs
      set_monitoring
      @version = version
      @page_title = @workflow.name.presence || "Automação de acompanhamento"
      flash.now[:alert] = "A intervenção ainda não pode ser publicada."
      render :builder, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid
    set_catalogs
    set_monitoring
    @version = version
    @page_title = @workflow.name.presence || "Automação de acompanhamento"
    flash.now[:alert] = "A intervenção ainda não pode ser publicada."
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

  def set_workflow
    @workflow = current_tenant.automation_workflows.find(params[:id])
  end

  def set_catalogs
    @trigger_options = AutomationRule::TRIGGERS
    @action_options = AutomationRule::INTERVENTION_ACTION_TYPES
    @status_options = Lead.status_options
    @automation_stage_options = Automation::StagePolicy.allowed_transition_stages
    @source_options = Lead.origin_options
    @broker_options = current_tenant.admin_users.active.order(:name).pluck(:name, :id)
    @template_options = current_tenant.whatsapp_templates.approved.ordered.pluck(:name, :name)
    @distribution_rule_options = current_tenant.distribution_rules.active.order(:name).pluck(:name, :id)
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
