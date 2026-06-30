class Admin::AutomationRulesController < Admin::BaseController
  before_action -> { check_permission!(:manage, :automacoes) }
  before_action :set_rule, only: [:edit, :update, :destroy, :toggle_active]

  def index
    @rules = current_tenant.automation_rules.ordered
    @workflows = current_tenant.automation_workflows.includes(:active_version).recent.limit(12)
    @recent_runs = AutomationRun.joins(:automation_rule).where(automation_rules: { tenant_id: current_tenant.id }).includes(:automation_rule, :lead).recent.limit(20)
    @page_title = "Automação de acompanhamento"
  end

  def new
    @rule = current_tenant.automation_rules.new(active: true, trigger_event: "lead_idle")
    load_options
    @page_title = "Nova intervenção automatizada"
  end

  def create
    @rule = current_tenant.automation_rules.new(rule_params)
    if @rule.save
      redirect_to admin_automation_rules_path, notice: "Intervenção criada."
    else
      load_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_options
    @page_title = "Editar intervenção automatizada"
  end

  def update
    if @rule.update(rule_params)
      redirect_to admin_automation_rules_path, notice: "Intervenção atualizada."
    else
      load_options
      render :edit, status: :unprocessable_entity
    end
  end

  def simulate
    @rule = params[:id].present? ? current_tenant.automation_rules.find(params[:id]) : current_tenant.automation_rules.new(active: true)
    @rule.assign_attributes(rule_params)
    load_options
    @simulation_result = Automation::Simulator.rule(
      trigger_event: @rule.trigger_event,
      conditions: @rule.conditions_hash,
      actions: @rule.action_list
    )
    @page_title = @rule.persisted? ? "Editar intervenção automatizada" : "Nova intervenção automatizada"
    flash.now[:notice] = "Simulação gerada sem salvar nem executar intervenções."
    render @rule.persisted? ? :edit : :new, status: :ok
  end

  def destroy
    @rule.destroy
    redirect_to admin_automation_rules_path, notice: "Intervenção removida."
  end

  def toggle_active
    @rule.update(active: !@rule.active)
    redirect_to admin_automation_rules_path, notice: "Intervenção #{@rule.active? ? 'ativada' : 'pausada'}."
  end

  # Cria uma intervenção de exemplo para mostrar acompanhamento horizontal.
  def create_example
    current_tenant.automation_rules.create!(
      name: "Resgate de lead frio",
      active: false,
      trigger_event: "lead_idle",
      conditions: { stage: "Em Atendimento", idle_hours: 48 },
      actions: [
        { type: "create_task", title: "Retomar contato com o lead", due_in_hours: 4 },
        { type: "send_whatsapp", message: "Olá {{nome}}, tudo bem? Ainda posso te ajudar com o imóvel?" },
        { type: "move_stage", to: "Represado" }
      ]
    )
    redirect_to admin_automation_rules_path, notice: "Intervenção de exemplo criada (pausada). Revise e ative quando quiser."
  end

  def test_webhook
    delivery = Automation::WebhookTestDelivery.call(
      url: params[:url],
      http_method: params[:http_method],
      headers: params[:headers],
      payload_template: params[:payload_template]
    )

    render json: {
      ok: delivery.status == "success",
      status: delivery.status,
      response_code: delivery.response_code,
      error: delivery.error_message
    }
  rescue => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  end

  private

  def set_rule
    @rule = current_tenant.automation_rules.find(params[:id])
  end

  def load_options
    @status_options = Lead.status_options
    @automation_stage_options = Automation::StagePolicy.allowed_transition_stages
    @source_options = Lead.origin_options
    @broker_options = current_tenant.admin_users.active.order(:name).pluck(:name, :id)
    @templates = current_tenant.whatsapp_templates.approved.ordered
  end

  def rule_params
    permitted = params.require(:automation_rule).permit(:name, :active, :trigger_event)
    permitted[:conditions] = clean_conditions
    permitted[:actions] = parse_actions
    permitted
  end

  def clean_conditions
    raw = params.dig(:automation_rule, :conditions) || {}
    {
      "stage" => raw[:stage].presence,
      "source" => raw[:source].presence,
      "idle_hours" => raw[:idle_hours].presence&.to_i
    }.compact
  end

  def parse_actions
    json = params.dig(:automation_rule, :actions_json).to_s
    return [] if json.blank?

    parsed = JSON.parse(json)
    actions = Array(parsed).map { |a| a.is_a?(Hash) ? a.slice("type", "title", "due_in_hours", "message", "template", "to", "admin_user_id", "body", "days", "url", "http_method", "headers", "payload_template") : nil }.compact
      .reject { |action| AutomationRule::VERTICAL_DISTRIBUTION_ACTION_TYPES.include?(action["type"].to_s) }
      .reject { |action| action["type"].to_s == "move_stage" && !Automation::StagePolicy.allowed_transition?(action["to"]) }
    actions
  rescue JSON::ParserError
    []
  end
end
