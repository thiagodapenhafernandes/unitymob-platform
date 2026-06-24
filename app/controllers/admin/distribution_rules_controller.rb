class Admin::DistributionRulesController < Admin::BaseController
  before_action -> { check_permission!(:manage, :distribution_rules) }
  before_action :set_rule, only: [:show, :edit, :update, :destroy, :toggle_active, :reorder_agents]
  before_action :load_meta_options, only: [:new, :create, :edit, :update]
  before_action :load_team_structure, only: [:new, :create, :edit, :update]

  def index
    @distribution_rules = DistributionRule.all.order(created_at: :desc)
    @holding_leads_count = Lead.represado.count
  end

  def show
    @agents_queue = @rule.distribution_rule_agents.includes(:admin_user).order(position: :asc)

    rule_leads = Lead.where(distribution_rule_id: @rule.id)
    @leads_total = rule_leads.count
    @leads_distributed = rule_leads.where.not(admin_user_id: nil).count
    @leads_today = rule_leads.where(created_at: Time.current.all_day).count
    @last_lead_at = rule_leads.maximum(:created_at)
    @leads_per_agent = rule_leads.where.not(admin_user_id: nil).group(:admin_user_id).count

    # Próximo corretor da fila (só faz sentido no modo rotativo).
    @next_agent_user_id = @rule.rotary? ? @rule.next_available_agent(@agents_queue)&.admin_user_id : nil
  end

  def new
    @distribution_rule = DistributionRule.new
    @distribution_rule.ensure_full_schedule
  end

  def create
    @distribution_rule = DistributionRule.new(rule_params)
    sync_agents
    populate_meta_forms_if_auto
    if @distribution_rule.save
      redirect_to admin_distribution_rule_path(@distribution_rule), notice: "Regra criada com sucesso."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @distribution_rule.assign_attributes(rule_params)
    sync_agents
    populate_meta_forms_if_auto
    if @distribution_rule.save
      redirect_to admin_distribution_rule_path(@distribution_rule), notice: "Regra atualizada com sucesso."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @rule.destroy
    redirect_to admin_distribution_rules_path, notice: "Regra excluída."
  end

  def toggle_active
    @rule.update(active: !@rule.active)
    redirect_to admin_distribution_rules_path, notice: "Status da regra atualizado."
  end

  def reorder_agents
    selected_ids = Array(params[:agent_ids]).compact_blank.map(&:to_i).uniq
    current_agents = @rule.distribution_rule_agents.order(position: :asc, id: :asc).to_a
    agents_by_id = current_agents.index_by(&:id)
    agent_ids = selected_ids.select { |agent_id| agents_by_id.key?(agent_id) }
    agent_ids += current_agents.map(&:id) - agent_ids

    @rule.transaction do
      agent_ids.each_with_index do |agent_id, index|
        agents_by_id.fetch(agent_id).update!(position: index + 1)
      end
    end

    redirect_to admin_distribution_rule_path(@rule), notice: "Ordem da fila atualizada."
  end

  private

  def set_rule
    @rule = DistributionRule.find(params[:id])
    @distribution_rule = @rule # For form compatibility
  end

  def load_meta_options
    @meta_structure = {}
    @meta_form_options_by_page = {}

    active_pages = MetaFacebookPage.where(active: true).includes(:meta_lead_forms).order(:name)
    active_pages.each do |page|
      forms = page.meta_lead_forms.sort_by { |form| form.name.to_s.downcase }
      forms_list = forms.map { |form| { id: form.form_id, name: form.name } }
      @meta_structure[page.page_id] = { name: page.name, forms: forms_list }
      @meta_form_options_by_page[page.page_id] = forms.map { |form| [ "#{form.name} · #{page.name}", form.form_id ] }
    end

    @all_page_options = active_pages.map { |page| [ page.name, page.page_id ] }
  end

  def load_team_structure
    active_users = AdminUser.active.order(:name).to_a
    @all_users_options = active_users.map { |u| [ u.name, u.id ] }
    @all_agents = active_users.map { |u| { id: u.id, name: u.name } }

    managers = AdminUser.account_members
                        .where(id: AdminUser.where.not(manager_id: nil).select(:manager_id))
                        .order(:name)

    users_by_id = active_users.index_by(&:id)
    @team_structure = managers.each_with_object({}) do |manager, structure|
      agent_ids = manager.descendant_ids
      agents = agent_ids.filter_map { |id| users_by_id[id] }.sort_by { |user| user.name.to_s.downcase }
      structure[manager.id] = {
        name: manager.name,
        agents: agents.map { |agent| { id: agent.id, name: agent.name } }
      }
    end

    @manager_options = managers.map { |m| [ m.name, m.id ] }
  end

  def populate_meta_forms_if_auto
    return unless @distribution_rule.auto_add_forms?
    page_ids = @distribution_rule.meta_page_ids.reject(&:blank?)
    @distribution_rule.meta_forms = []
    return if page_ids.blank?

    pages = MetaFacebookPage.where(page_id: page_ids)
    @distribution_rule.meta_forms = MetaLeadForm.where(meta_facebook_page_id: pages.select(:id)).pluck(:form_id)
  end

  # A composição da fila é reconciliada a partir do select de corretores
  # (`agent_select`), que é a fonte única de verdade da participação. As linhas
  # nested da fila ("distribution_rule_agents_attributes") são usadas apenas como
  # metadados de peso/posição, casadas por admin_user_id. Isso evita perder
  # corretores quando o chip e a fila ficam dessincronizados no front.
  def sync_agents
    metadata = nested_agent_metadata
    selected_ids =
      if params.key?(:agent_select)
        Array(params[:agent_select]).compact_blank.map(&:to_i).uniq
      else
        metadata.keys
      end

    existing_agents = @distribution_rule.distribution_rule_agents.index_by(&:admin_user_id)

    existing_agents.each do |admin_user_id, agent|
      agent.mark_for_destruction unless selected_ids.include?(admin_user_id)
    end

    selected_ids.each_with_index do |admin_user_id, index|
      agent = existing_agents[admin_user_id] || @distribution_rule.distribution_rule_agents.build(admin_user_id: admin_user_id)
      meta = metadata[admin_user_id] || {}
      agent.position = (meta[:position].presence || index + 1).to_i
      agent.weight = (meta[:weight].presence || agent.weight.presence || 1).to_i
    end
  end

  # { admin_user_id => { weight:, position: } } a partir das linhas nested da fila,
  # ignorando linhas marcadas para destruição ou sem corretor.
  def nested_agent_metadata
    raw = params.dig(:distribution_rule, :distribution_rule_agents_attributes)
    return {} if raw.blank?

    raw.values.each_with_object({}) do |row, acc|
      admin_user_id = row[:admin_user_id].to_i
      next if admin_user_id.zero?
      next if ActiveModel::Type::Boolean.new.cast(row[:_destroy])

      acc[admin_user_id] = { weight: row[:weight], position: row[:position] }
    end
  end

  def rule_params
    # For JSONB fields like represamento_schedule, we permit the whole hash.
    # Os agentes da fila são tratados em sync_agents (fonte = agent_select), por
    # isso distribution_rule_agents_attributes NÃO é permitido aqui.
    params.require(:distribution_rule).permit(
      :name, :business_type, :active,
      :source_meta, :source_webhook, :source_portal, :source_site,
      :distribution_mode,
      :pocket_active, :pocket_time,
      :represamento_active, :auto_add_forms,
      :min_price, :max_price,
      :notify_whatsapp, :notify_email, :notify_webhook, :notify_push,
      :webhook_url,
      :require_active_checkin, :require_inside_radius, :require_active_shift, :exclude_suspicious_checkins,
      admin_user_ids: [],
      meta_forms: [],
      meta_page_ids: [],
      webhook_tags: [],
      neighborhoods: [],
      notify_webhook_urls: [],
      checkin_store_ids: [],
      represamento_schedule: {},
      custom_filters: {}
    ).tap do |perms|
      # Selects multiplos enviam um "" inicial (hidden field do Rails). Limpar para
      # não poluir os arrays JSONB (que viram chips vazios fantasmas ao reabrir).
      %i[meta_forms meta_page_ids webhook_tags neighborhoods notify_webhook_urls].each do |key|
        perms[key] = Array(perms[key]).compact_blank if perms[key].is_a?(Array)
      end
      if perms[:checkin_store_ids].is_a?(Array)
        perms[:checkin_store_ids] = perms[:checkin_store_ids].compact_blank.map(&:to_i)
      end
    end
  end
end
