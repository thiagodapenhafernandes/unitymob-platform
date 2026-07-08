class Admin::DistributionRulesController < Admin::BaseController
  before_action -> { check_permission!(:manage, :distribution_rules) }
  before_action :set_rule, only: [:show, :edit, :update, :destroy, :toggle_active, :reorder_agents]
  before_action :load_meta_options, only: [:new, :create, :edit, :update]
  before_action :load_team_structure, only: [:new, :create, :edit, :update]

  def index
    @distribution_rules = current_tenant.distribution_rules.order(created_at: :desc)
    @holding_leads_count = current_tenant.leads.represado.count
  end

  def show
    @agents_queue = @rule.distribution_rule_agents.includes(:admin_user).order(position: :asc)

    rule_leads = current_tenant.leads.where(distribution_rule_id: @rule.id)
    @leads_total = rule_leads.count
    @leads_distributed = rule_leads.where.not(admin_user_id: nil).count
    @leads_today = rule_leads.where(created_at: Time.current.all_day).count
    @last_lead_at = rule_leads.maximum(:created_at)
    @leads_per_agent = rule_leads.where.not(admin_user_id: nil).group(:admin_user_id).count

    # Próximo corretor da fila (só faz sentido no modo rotativo).
    @next_agent_user_id = @rule.rotary? ? @rule.next_available_agent(@agents_queue)&.admin_user_id : nil
  end

  def new
    @distribution_rule = current_tenant.distribution_rules.new
    @distribution_rule.ensure_full_schedule
  end

  def create
    @distribution_rule = current_tenant.distribution_rules.new(rule_params)
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
    @rule = current_tenant.distribution_rules.find(params[:id])
    @distribution_rule = @rule # For form compatibility
  end

  def load_meta_options
    @meta_structure = {}
    @meta_form_options_by_page = {}

    active_pages = tenant_meta_pages.where(active: true).includes(:meta_lead_forms).order(:name)
    active_pages.each do |page|
      forms = page.meta_lead_forms.sort_by { |form| form.name.to_s.downcase }
      forms_list = forms.map { |form| { id: form.form_id, name: form.name } }
      @meta_structure[page.page_id] = { name: page.name, forms: forms_list }
      @meta_form_options_by_page[page.page_id] = forms.map { |form| [ "#{form.name} · #{page.name}", form.form_id ] }
    end

    @all_page_options = active_pages.map { |page| [ page.name, page.page_id ] }
  end

  def load_team_structure
    eligible_users = eligible_distribution_admin_users.to_a
    @all_users_options = eligible_users.map { |u| [ u.name, u.id ] }
    # Payload do filtro leva TODOS os elegíveis (sem corte de área): a área é
    # dinâmica na tela (Tipo de negócio) e quem filtra reativamente é o front.
    # No save, sync_agents revalida com a área submetida (fail-closed).
    @all_agents = eligible_distribution_admin_users(area_scope: false).map { |u| distribution_hierarchy_user_payload(u) }
    # Filtro de hierarquia só faz sentido para NÍVEIS INTERMEDIÁRIOS (gestores):
    # o dono da conta é o topo fixo (estamos dentro da conta dele) e o nível
    # folha ("Corretor") duplicaria o próprio campo "Corretores na regra".
    @distribution_hierarchy_profiles = distribution_hierarchy_profiles.reject { |p| p.tenant_owner? || p.agent? }
    @distribution_hierarchy_locked_user_id = tenant_owner? ? nil : current_admin_user.id
  end

  def populate_meta_forms_if_auto
    return unless @distribution_rule.auto_add_forms?
    page_ids = @distribution_rule.meta_page_ids.reject(&:blank?)
    @distribution_rule.meta_forms = []
    return if page_ids.blank?

    pages = tenant_meta_pages.where(page_id: page_ids)
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
    eligible_ids = eligible_distribution_admin_users.where(id: selected_ids).pluck(:id)
    selected_ids = selected_ids.select { |admin_user_id| eligible_ids.include?(admin_user_id) }

    existing_agents = @distribution_rule.distribution_rule_agents.index_by(&:admin_user_id)

    existing_agents.each do |admin_user_id, agent|
      agent.mark_for_destruction unless selected_ids.include?(admin_user_id) && eligible_ids.include?(admin_user_id)
    end

    selected_ids.each_with_index do |admin_user_id, index|
      agent = existing_agents[admin_user_id] || @distribution_rule.distribution_rule_agents.build(admin_user_id: admin_user_id)
      agent.tenant = current_tenant
      meta = metadata[admin_user_id] || {}
      agent.position = (meta[:position].presence || index + 1).to_i
      agent.weight = (meta[:weight].presence || agent.weight.presence || 1).to_i
    end
  end

  def eligible_distribution_admin_users(area_scope: true)
    # Dono da conta fica fora da fila de distribuição: ele já enxerga e pode
    # assumir qualquer lead (escopo total) — participação é implícita, não
    # precisa (nem deve) aparecer como opção selecionável.
    scope = current_tenant.admin_users.active.includes(:profile).where.not(profile_id: nil)
                          .where(profiles: { axis: Profile::AXES[:vertical] })
                          .where.not(profiles: { key: "tenant_owner" })
                          .references(:profile)

    # Área da regra (business_type) restringe por atuação do corretor:
    # regra de venda só distribui a quem atua em venda/ambos; locação idem.
    # area_scope: false → dataset completo para o filtro reativo do front.
    if area_scope
      case rule_business_type_for_eligibility
      when "venda"   then scope = scope.where(acting_type: [AdminUser.acting_types[:sales], AdminUser.acting_types[:both]])
      when "locacao" then scope = scope.where(acting_type: [AdminUser.acting_types[:rentals], AdminUser.acting_types[:both]])
      end
    end

    unless tenant_owner?
      scope = scope.where(id: current_admin_user.team_scope_ids)
    end

    scope.order(:name)
  end

  def rule_business_type_for_eligibility
    params.dig(:distribution_rule, :business_type).presence || @distribution_rule&.business_type
  end

  # Páginas Meta pertencem à integração de um admin (UserMetaIntegration) —
  # o escopo da conta vem do tenant desse admin. Sem isso, o select de páginas
  # vazava páginas de OUTRAS contas.
  def tenant_meta_pages
    MetaFacebookPage.joins(user_meta_integration: :admin_user)
                    .where(admin_users: { tenant_id: current_tenant.id })
  end

  def distribution_hierarchy_profiles
    profiles = current_tenant.profiles.ordered_vertical.to_a
    return profiles if tenant_owner? || current_admin_user.vertical_profile.blank?

    current_position = current_admin_user.vertical_profile.position.to_i
    profiles.select { |profile| profile.position.to_i >= current_position }
  end

  def distribution_hierarchy_user_payload(user)
    {
      id: user.id,
      name: user.name,
      profile_id: user.profile_id,
      profile_name: user.profile&.name,
      manager_id: user.manager_id,
      rentals_manager_id: (user.rentals_manager_id if user.class.column_names.include?("rentals_manager_id")),
      acting_type: user.acting_type
    }
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
      :auto_update_agents_enabled, :auto_update_shuffle_agents,
      admin_user_ids: [],
      meta_forms: [],
      meta_page_ids: [],
      webhook_tags: [],
      neighborhoods: [],
      notify_webhook_urls: [],
      checkin_store_ids: [],
      auto_update_trigger: [],
      hierarchy_manager_ids: [],
      represamento_schedule: {},
      custom_filters: {}
    ).tap do |perms|
      # Selects multiplos enviam um "" inicial (hidden field do Rails). Limpar para
      # não poluir os arrays JSONB (que viram chips vazios fantasmas ao reabrir).
      %i[meta_forms meta_page_ids webhook_tags neighborhoods notify_webhook_urls].each do |key|
        perms[key] = Array(perms[key]).compact_blank if perms[key].is_a?(Array)
      end

      # Gestores do filtro: só ids de usuários reais DESTA conta (anti-injeção).
      # Antes da migration (coluna ausente), descarta em vez de estourar.
      if !DistributionRule.column_names.include?("hierarchy_manager_ids")
        perms.delete(:hierarchy_manager_ids)
      elsif perms[:hierarchy_manager_ids].is_a?(Array)
        requested_ids = perms[:hierarchy_manager_ids].compact_blank.map(&:to_i).uniq
        perms[:hierarchy_manager_ids] = current_tenant.admin_users.where(id: requested_ids).pluck(:id)
      end
      if perms[:checkin_store_ids].is_a?(Array)
        perms[:checkin_store_ids] = perms[:checkin_store_ids].compact_blank.map(&:to_i)
      end
      unless DistributionRule.column_names.include?("auto_update_agents_enabled")
        perms.delete(:auto_update_agents_enabled)
      end
      unless DistributionRule.column_names.include?("auto_update_shuffle_agents")
        perms.delete(:auto_update_shuffle_agents)
      end
      unless DistributionRule.column_names.include?("auto_update_trigger")
        perms.delete(:auto_update_trigger)
      end
      if perms[:auto_update_trigger].is_a?(Array)
        perms[:auto_update_trigger] = perms[:auto_update_trigger].compact_blank
      end
      %i[min_price max_price].each do |key|
        perms[key] = parse_brl_decimal(perms[key]) if perms[key].present?
      end
      unless DistributionRule.pocket_requires_secure_push?
        perms[:pocket_active] = "0"
      end
    end
  end

  def parse_brl_decimal(value)
    normalized = value.to_s.gsub(/[^\d,\.]/, "")
    return nil if normalized.blank?

    normalized = normalized.delete(".").tr(",", ".") if normalized.include?(",")
    BigDecimal(normalized)
  rescue ArgumentError
    value
  end
end
