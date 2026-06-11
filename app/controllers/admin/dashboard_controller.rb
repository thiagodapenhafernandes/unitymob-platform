class Admin::DashboardController < Admin::BaseController
  def index
    unless current_admin_user.admin?
      redirect_to field_root_path
      return
    end

    @is_admin_view = current_admin_user.admin?

    # Scopes: admin vê tudo, corretor vê só o que é dele.
    habitation_scope = @is_admin_view ? Habitation : Habitation.where(admin_user_id: current_admin_user.id)
    lead_scope       = @is_admin_view ? Lead       : Lead.where(admin_user_id: current_admin_user.id)
    captacao_scope   = @is_admin_view ? Captacao   : Captacao.where(corretor_id: current_admin_user.id)

    # ================= Imóveis =================
    @properties_count    = habitation_scope.active.count
    @featured_count      = habitation_scope.featured.count
    @for_sale_count      = habitation_scope.active.where(status: ['Venda']).count
    @for_rent_count      = habitation_scope.active.where(status: ['Locação', 'Locacao', 'Aluguel']).count
    @developments_count  = habitation_scope.empreendimentos.count
    @proprietors_count   = @is_admin_view ? Proprietor.count : 0
    @total_sale_value    = habitation_scope.active.where("valor_venda_cents > 0").sum(:valor_venda_cents).to_f / 100.0
    @avg_sale_value      = habitation_scope.active.where("valor_venda_cents > 0").average(:valor_venda_cents).to_f / 100.0
    @recent_properties   = habitation_scope.newest_first.limit(6)

    # ================= Equipe (só admin) =================
    if @is_admin_view
      @brokers_active     = AdminUser.active.count
      @brokers_inactive   = AdminUser.inactive.count
      @brokers_with_vista = AdminUser.where.not(vista_id: nil).count
      @field_agents_count = AdminUser.where(field_agent_enabled: true).count

      @top_brokers = AdminUser
        .joins(:habitations)
        .where(habitations: { status: [nil, "Venda", "Locação", "Locacao", "Aluguel"] })
        .group("admin_users.id", "admin_users.name")
        .select("admin_users.id, admin_users.name, COUNT(habitations.id) AS ct")
        .order("ct DESC")
        .limit(6)
    else
      @brokers_active = @brokers_inactive = @brokers_with_vista = @field_agents_count = 0
      @top_brokers = []
    end

    # ================= Lojas / Field (só admin) =================
    if @is_admin_view
      @stores_count             = Store.count
      @stores_active_count      = Store.active.count
      @active_checkins_count    = CheckIn.where(status: :active).count
      @today_checkins_count     = CheckIn.today.count
      @suspicious_checkins      = CheckIn.where(suspicious: true).count
      @pending_manual_requests  = ManualCheckinRequest.pending.count
      @top_stores = CheckIn
        .where("checked_in_at >= ?", 30.days.ago)
        .joins(:store)
        .group("stores.id", "stores.name")
        .select("stores.id, stores.name, COUNT(check_ins.id) AS ct")
        .order("ct DESC")
        .limit(5)
    else
      @stores_count = @stores_active_count = 0
      @active_checkins_count = current_admin_user.active_check_in.present? ? 1 : 0
      @today_checkins_count = CheckIn.where(admin_user_id: current_admin_user.id).today.count
      @suspicious_checkins = 0
      @pending_manual_requests = 0
      @top_stores = []
    end
    @field_feature_enabled = Setting.get("field_checkin_enabled", "false").to_s == "true"

    # ================= Leads =================
    @total_leads          = lead_scope.count
    @new_leads            = lead_scope.where(status: [Lead.default_status, nil]).count
    @leads_today          = lead_scope.where("created_at >= ?", Date.current.beginning_of_day).count
    @leads_last_7_days    = lead_scope.where("created_at >= ?", 7.days.ago).count
    @leads_last_30_days   = lead_scope.where("created_at >= ?", 30.days.ago).count
    @holding_leads        = @is_admin_view ? Lead.holding.count : 0
    @leads_by_status      = lead_scope.group(:status).count
    @leads_per_day        = leads_time_series(30, lead_scope)

    # ================= Regras de distribuição (só admin) =================
    if @is_admin_view
      @distribution_rules_total  = DistributionRule.count
      @distribution_rules_active = DistributionRule.active.count
      @rules_with_checkin        = DistributionRule.where(require_active_checkin: true).count
    else
      @distribution_rules_total = @distribution_rules_active = @rules_with_checkin = 0
    end

    # ================= Sync Vista (só admin) =================
    if @is_admin_view
      @sync_errors_count   = Habitation.where(last_sync_status: 'error').count
      @total_synced_count  = Habitation.where.not(last_sync_at: nil).count
      @last_syncs          = Habitation.where.not(last_sync_at: nil).order(last_sync_at: :desc).limit(5)
    else
      @sync_errors_count = @total_synced_count = 0
      @last_syncs = []
    end

    # ================= Hoje =================
    beginning = Date.current.beginning_of_day
    @today_captacoes       = captacao_scope.where(created_at: beginning..).count
    @today_new_habitations = habitation_scope.where("COALESCE(data_atualizacao_crm, created_at) >= ?", beginning).count
    @today_audit_events    = @is_admin_view ? CheckinAuditLog.where(created_at: beginning..).count : 0

    # ================= Listas recentes =================
    @recent_habitations = habitation_scope
      .where.not(data_atualizacao_crm: nil)
      .order(data_atualizacao_crm: :desc)
      .limit(6)

    @recent_captacoes = captacao_scope
      .includes(:corretor)
      .order(updated_at: :desc)
      .limit(5)

    @drafts_count = captacao_scope.draft.count

    # ================= Distribuição por categoria =================
    @habitations_by_category = habitation_scope.active.group(:categoria).count.sort_by { |_, v| -v }.first(6)

    # ================= Atividade recente =================
    @recent_audit_logs = if @is_admin_view
                          CheckinAuditLog.includes(:admin_user, :actor_admin_user).order(created_at: :desc).limit(6)
                        else
                          CheckinAuditLog.where(admin_user_id: current_admin_user.id).order(created_at: :desc).limit(6)
                        end
    @recent_leads = lead_scope.order(created_at: :desc).limit(6)
  end

  private

  def leads_time_series(days, scope = Lead)
    start_date = days.days.ago.to_date
    rows = scope
      .where("created_at >= ?", start_date.beginning_of_day)
      .group("DATE(created_at)")
      .count
    (0...days).map do |i|
      d = start_date + i
      [d, rows[d] || 0]
    end
  end
end
