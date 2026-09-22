class Admin::WhatsappResponseFlowsController < Admin::BaseController
  requires_permission :view, :whatsapp_response_flows, only: [:index, :show]
  requires_permission :manage, :whatsapp_response_flows, except: [:index, :show]
  before_action :set_flow, only: [:show, :edit, :update, :destroy]

  def index
    @flows = current_tenant.whatsapp_response_flows.includes(:whatsapp_template, :automation_workflow).ordered
    @receptive_numbers = current_tenant.whatsapp_sender_numbers.where.not(receptive_response_flow_id: nil).group_by(&:receptive_response_flow_id)
    @page_title = "Fluxos de Resposta WhatsApp"
  end

  def show
    redirect_to edit_admin_whatsapp_response_flow_path(@flow)
  end

  def new
    template = approved_template_scope.find_by(id: params[:whatsapp_template_id])
    template = nil if template && template.interactive_buttons.none? { |button| button["actionable_reply"] }
    existing = template && current_tenant.whatsapp_response_flows.find_by(whatsapp_template_id: template.id)
    return redirect_to(edit_admin_whatsapp_response_flow_path(existing), notice: "Este template já tem um fluxo de resposta.") if existing

    @flow = current_tenant.whatsapp_response_flows.new(
      whatsapp_template: template,
      name: template ? flow_name_for(template) : nil,
      button_actions: default_button_actions(template)
    )
    load_form_options
  end

  def create
    @flow = current_tenant.whatsapp_response_flows.new(flow_params)
    @flow.created_by = current_admin_user

    if @flow.save
      sync_receptive_sender_number!
      Automation::WhatsappResponseFlowWorkflowSync.call(@flow)
      redirect_to admin_whatsapp_response_flows_path, notice: "Fluxo de resposta criado."
    else
      load_form_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @flow.button_actions = default_button_actions(@flow.whatsapp_template).deep_merge(@flow.button_actions.to_h)
    load_form_options
  end

  def update
    # Botões que o template não tem mais (ou que a tela não renderizou) mantêm a decisão salva: nada se perde ao salvar.
    attrs = flow_params.except(:whatsapp_template_id) # o template não muda depois que o fluxo é criado
    attrs[:button_actions] = @flow.button_actions.to_h.merge(attrs[:button_actions].to_h) if attrs.key?(:button_actions)
    if @flow.update(attrs)
      sync_receptive_sender_number!
      Automation::WhatsappResponseFlowWorkflowSync.call(@flow)
      redirect_to admin_whatsapp_response_flows_path, notice: "Fluxo de resposta atualizado."
    else
      load_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @flow.destroy
    redirect_to admin_whatsapp_response_flows_path, notice: "Fluxo de resposta removido."
  end

  private

  def set_flow
    @flow = current_tenant.whatsapp_response_flows.find(params[:id])
  end

  def load_form_options
    @templates = selectable_templates
    @distribution_rules = current_tenant.distribution_rules.active.includes(distribution_rule_agents: :admin_user).order(:name)
    @user_options = current_tenant.admin_users.active.order(:name).pluck(:name, :id)
    @automation_workflow_options = automation_workflow_options
    @distribution_rule_agent_options = @distribution_rules.each_with_object({}) do |rule, memo|
      memo[rule.id.to_s] = rule.eligible_distribution_rule_agents(rule.distribution_rule_agents)
                              .map { |agent| [agent.admin_user.name, agent.admin_user_id] }
                              .sort_by { |name, _id| name.to_s.downcase }
    end
    @receptive_sender_number = receptive_sender_number_for(@flow)
    @set_as_receptive_for_sender = @receptive_sender_number&.receptive_response_flow_id == @flow.id
  end

  # Automações do construtor que começam com o clique em um botão (as espelhadas de fluxos de resposta ficam de fora).
  def automation_workflow_options
    current_tenant.automation_workflows.where.not(status: "archived").includes(:active_version).order(:name).filter_map do |workflow|
      definition = workflow.active_version&.definition_hash || workflow.versions.order(:version_number).last&.definition_hash || {}
      entry = Array(definition[:nodes]).find { |node| node[:type].to_s == "entry" }
      next unless entry && entry.dig(:config, :trigger).to_s == "whatsapp_flow_button"

      ["#{workflow.name}#{' (rascunho: publique para funcionar)' unless workflow.status == 'active'}", workflow.id]
    end
  end

  # Templates que podem originar um novo fluxo: aprovados, com botão de resposta e ainda sem fluxo.
  def selectable_templates
    used_ids = current_tenant.whatsapp_response_flows.pluck(:whatsapp_template_id)
    approved_template_scope.where.not(id: used_ids).select { |template| template.interactive_buttons.any? { |button| button["actionable_reply"] } }
  end

  def approved_template_scope
    current_tenant.whatsapp_templates.approved.for_response_flows.ordered
  end

  def flow_name_for(template)
    "#{template.usage_context_label}: #{template.name}".truncate(120)
  end

  def default_button_actions(template)
    Array(template&.interactive_buttons).each_with_object({}) do |button, memo|
      next unless button["actionable_reply"]

      key = button["key"].to_s
      memo[key] = {
        "button_key" => key,
        "button_text" => button["text"].to_s,
        "action" => "record_only",
        "business_hours" => WhatsappResponseFlow::DEFAULT_BUSINESS_HOURS
      }
    end
  end

  def flow_params
    params.require(:whatsapp_response_flow).permit(
      :name,
      :whatsapp_template_id,
      :active,
      button_actions: {}
    )
  end

  def sync_receptive_sender_number!
    sender = receptive_sender_number_for(@flow)
    return if sender.blank?

    if ActiveModel::Type::Boolean.new.cast(params[:set_as_receptive_for_sender])
      sender.update!(receptive_response_flow: @flow)
    elsif sender.receptive_response_flow_id == @flow.id
      sender.update!(receptive_response_flow: nil)
    end
  end

  def receptive_sender_number_for(flow)
    waba_id = flow.whatsapp_template&.waba_id.presence
    return if waba_id.blank?

    selected = current_tenant.whatsapp_sender_numbers.active.find_by(id: params[:whatsapp_sender_number_id])
    return selected if selected&.waba_id == waba_id

    current_tenant.whatsapp_sender_numbers.active.ordered.find_by(waba_id: waba_id)
  end
end
