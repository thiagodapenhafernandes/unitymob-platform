class Admin::AutomationRulesController < Admin::BaseController
  before_action -> { check_permission!(:manage, :automacoes) }
  before_action :set_rule, only: [:edit, :update, :destroy, :toggle_active]

  def index
    @rules = AutomationRule.ordered
    @recent_runs = AutomationRun.includes(:automation_rule, :lead).recent.limit(20)
    @page_title = "Automação"
  end

  def new
    @rule = AutomationRule.new(active: true, trigger_event: "lead_idle")
    load_options
    @page_title = "Nova regra de automação"
  end

  def create
    @rule = AutomationRule.new(rule_params)
    if @rule.save
      redirect_to admin_automation_rules_path, notice: "Regra criada."
    else
      load_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_options
    @page_title = "Editar regra"
  end

  def update
    if @rule.update(rule_params)
      redirect_to admin_automation_rules_path, notice: "Regra atualizada."
    else
      load_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @rule.destroy
    redirect_to admin_automation_rules_path, notice: "Regra removida."
  end

  def toggle_active
    @rule.update(active: !@rule.active)
    redirect_to admin_automation_rules_path, notice: "Regra #{@rule.active? ? 'ativada' : 'pausada'}."
  end

  # Cria uma regra de exemplo (didática) para o usuário entender o fluxo.
  def create_example
    AutomationRule.create!(
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
    redirect_to admin_automation_rules_path, notice: "Regra de exemplo criada (pausada). Revise e ative quando quiser."
  end

  private

  def set_rule
    @rule = AutomationRule.find(params[:id])
  end

  def load_options
    @status_options = Lead.status_options
    @source_options = Lead.origin_options
    @broker_options = AdminUser.active.order(:name).pluck(:name, :id)
    @templates = WhatsappTemplate.approved.ordered
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
    Array(parsed).map { |a| a.is_a?(Hash) ? a.slice("type", "title", "due_in_hours", "message", "template", "to", "admin_user_id", "body", "days") : nil }.compact
  rescue JSON::ParserError
    []
  end
end
