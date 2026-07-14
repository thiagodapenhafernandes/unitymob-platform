class Admin::DashboardController < Admin::BaseController
  include DeviceRequest

  DASHBOARD_SECTIONS = %w[charts acquisition funnel status rankings operations support].freeze
  DASHBOARD_TABS = %w[overview leads properties field].freeze
  DASHBOARD_PERIODS = [7, 30, 90].freeze

  before_action :require_dashboard_admin!
  before_action :set_dashboard_context

  def index
    load_overview_slice
  end

  def section
    section_name = params[:section].to_s
    raise ActiveRecord::RecordNotFound unless DASHBOARD_SECTIONS.include?(section_name)

    @dashboard_tab = "all" if params[:tab].blank?
    send("load_#{section_name}_slice")
    render partial: "admin/dashboard/sections/#{section_name}", layout: false
  end

  private

  def require_dashboard_admin!
    return if tenant_owner? || can?(:view, :dashboard)
    return if desktop_device_request?

    redirect_to field_root_path
  end

  def set_dashboard_context
    @is_admin_view = tenant_owner?
    @dashboard_period = params[:period].to_i.presence_in(DASHBOARD_PERIODS) || 30
    @dashboard_broker_id = @is_admin_view ? params[:broker_id].presence&.to_i : current_admin_user.id
    @dashboard_brokers = @is_admin_view ? current_tenant.admin_users.active.order(:name).select(:id, :name) : []
    @habitation_scope = scoped_dashboard_habitations
    @lead_scope = scoped_dashboard_leads
    @captacao_scope = scoped_dashboard_captacoes
    @field_feature_enabled = Setting.get("field_checkin_enabled", "false").to_s == "true"
    requested_tab = params[:tab].to_s.presence_in(DASHBOARD_TABS) || "overview"
    @dashboard_tab = requested_tab == "field" && !@field_feature_enabled ? "overview" : requested_tab
    @dashboard_updated_at = Time.current
    @dashboard_window_start = dashboard_window_start
  end

  # Os ~18 counts do overview rodavam em TODA visita ao dashboard. KPIs de
  # visão geral toleram 45s de atraso — cache curto por conta+usuário (o escopo
  # visível depende do usuário). As seções (charts/funnel/...) seguem ao vivo.
  def load_overview_slice
    metrics = Rails.cache.fetch(
      ["dashboard-overview", current_tenant.id, current_admin_user.id, @dashboard_period, @dashboard_broker_id],
      expires_in: 45.seconds
    ) { compute_overview_metrics }
    metrics.each { |name, value| instance_variable_set("@#{name}", value) }
  end

  def compute_overview_metrics
    active_habitations = @habitation_scope.active
    beginning = Date.current.beginning_of_day

    @properties_count = active_habitations.count
    @featured_count = @habitation_scope.featured.count
    @developments_count = @habitation_scope.empreendimentos.count

    @brokers_active = @is_admin_view ? current_tenant.admin_users.active.count : 0
    @stores_active_count = @is_admin_view ? current_tenant.stores.active.count : 0
    @active_checkins_count = @is_admin_view ? CheckIn.where(tenant: current_tenant, status: :active).count : (current_admin_user.active_check_in.present? ? 1 : 0)
    @today_checkins_count = @is_admin_view ? CheckIn.where(tenant: current_tenant).today.count : CheckIn.where(tenant: current_tenant, admin_user_id: current_admin_user.id).today.count
    @suspicious_checkins = @is_admin_view ? CheckIn.where(tenant: current_tenant, suspicious: true).count : 0
    @pending_manual_requests = @is_admin_view ? ManualCheckinRequest.where(tenant: current_tenant).pending.count : 0

    @new_leads = @lead_scope.where(status: [Lead.default_status, nil]).count
    @leads_today = @lead_scope.where("created_at >= ?", beginning).count
    @leads_last_7_days = @lead_scope.where("created_at >= ?", 7.days.ago).count
    current_period_leads = @lead_scope.where("created_at >= ?", dashboard_window_start).count
    previous_period_leads = @lead_scope.where(created_at: previous_dashboard_window).count
    @leads_period_change = percentage_change(current_period_leads, previous_period_leads)
    @holding_leads = @is_admin_view ? current_tenant.leads.holding.count : 0

    @distribution_rules_total = @is_admin_view ? current_tenant.distribution_rules.count : 0
    @distribution_rules_active = @is_admin_view ? current_tenant.distribution_rules.active.count : 0
    @rules_with_checkin = @is_admin_view ? current_tenant.distribution_rules.where(require_active_checkin: true).count : 0

    @sync_errors_count = @is_admin_view ? current_tenant.habitations.where(last_sync_status: "error").count : 0
    @today_captacoes = @captacao_scope.where(created_at: beginning..).count
    @today_new_habitations = @habitation_scope.where("COALESCE(data_atualizacao_crm, created_at) >= ?", beginning).count
    draft_captacoes = @captacao_scope.where(intake_status: [nil, "draft"])
    @drafts_count = draft_captacoes.count
    @stale_drafts_count = draft_captacoes.where("habitations.updated_at < ?", 30.days.ago).count
    @oldest_draft_updated_at = draft_captacoes.minimum("habitations.updated_at")

    %i[properties_count featured_count developments_count brokers_active stores_active_count
       active_checkins_count today_checkins_count suspicious_checkins pending_manual_requests
       new_leads leads_today leads_last_7_days holding_leads
       distribution_rules_total distribution_rules_active rules_with_checkin
       sync_errors_count today_captacoes today_new_habitations drafts_count
       stale_drafts_count oldest_draft_updated_at leads_period_change]
      .index_with { |name| instance_variable_get("@#{name}") }
  end

  def load_charts_slice
    @lead_date_min = dashboard_window_start.to_date
    @lead_date_max = Date.current
    @selected_lead_date = selected_lead_date
    @leads_by_status = @lead_scope.group(:status).count

    if @selected_lead_date
      @leads_series = leads_hourly_series(@selected_lead_date, @lead_scope)
      @leads_total = @leads_series.sum { |_, count| count }
      @leads_chart_mode = "hourly"
      @leads_drilldown_urls = Array.new(24) { admin_leads_path(start_date: @selected_lead_date.iso8601, end_date: @selected_lead_date.iso8601, broker_id: @dashboard_broker_id) }
    else
      @leads_series = leads_time_series(30, @lead_scope)
      @leads_total = @lead_scope.where("created_at >= ?", dashboard_window_start).count
      @leads_chart_mode = "daily"
      @leads_drilldown_urls = @leads_series.map { |date, _| admin_leads_path(start_date: date.iso8601, end_date: date.iso8601, broker_id: @dashboard_broker_id) }
    end
  end

  def load_acquisition_slice
    result = Dashboard::LeadAcquisitionQuery.new(
      scope: @lead_scope,
      starts_at: dashboard_window_start,
      tenant: current_tenant
    ).call
    result.each { |name, value| instance_variable_set("@acquisition_#{name}", value) }
  end

  def load_funnel_slice
    @commercial_funnel_rows = commercial_funnel_rows
  end

  def load_status_slice
    @leads_by_status = @lead_scope.where("created_at >= ?", dashboard_window_start).group(:status).count
    @lead_status_rows = @leads_by_status.map do |status, count|
      canonical_status = Lead.status_value(status.presence || Lead.default_status)
      {
        label: canonical_status,
        count: count,
        path: admin_leads_path(
          status: canonical_status,
          start_date: dashboard_window_start.to_date.iso8601,
          end_date: Date.current.iso8601
        )
      }
    end.sort_by { |row| -row[:count] }
  end

  def load_rankings_slice
    @top_brokers = if @is_admin_view
                     current_tenant.admin_users
                       .joins(:habitations)
                       .where(habitations: { status: [nil, "Venda", "Locação", "Locacao", "Aluguel"] })
                       .group("admin_users.id", "admin_users.name")
                       .select("admin_users.id, admin_users.name, COUNT(habitations.id) AS ct")
                       .order("ct DESC")
                       .limit(6)
                   else
                     []
                   end

    @broker_performance = broker_performance_rows

    @top_stores = if @is_admin_view
                    CheckIn
                      .where(tenant: current_tenant)
                      .where("checked_in_at >= ?", 30.days.ago)
                      .joins(:store)
                      .group("stores.id", "stores.name")
                      .select("stores.id, stores.name, COUNT(check_ins.id) AS ct")
                      .order("ct DESC")
                      .limit(5)
                  else
                    []
                  end
  end

  def load_operations_slice
    @bs_to_ax = { "success" => "green", "danger" => "red", "warning" => "amber", "info" => "blue", "primary" => "blue", "secondary" => "gray", "dark" => "gray" }
    @recent_audit_logs = if @is_admin_view
                           current_tenant.checkin_audit_logs.includes(:admin_user, :actor_admin_user, check_in: :store).order(created_at: :desc).limit(6)
                         else
                           current_tenant.checkin_audit_logs.includes(:actor_admin_user, check_in: :store).where(admin_user_id: current_admin_user.id).order(created_at: :desc).limit(6)
                         end
    @recent_habitations = @habitation_scope
      .includes(:address)
      .where.not(data_atualizacao_crm: nil)
      .order(data_atualizacao_crm: :desc)
      .limit(6)
    @catalog_quality_metrics = catalog_quality_metrics
  end

  def load_support_slice
    active_habitations = @habitation_scope.active

    @recent_captacoes = @captacao_scope
      .includes(:admin_user, :address)
      .order(updated_at: :desc)
      .limit(5)
    @habitations_by_category = active_habitations.group(:categoria).count.sort_by { |_, v| -v }.first(6)
    @for_sale_count = active_habitations.where(status: ["Venda"]).count
    @total_sale_value = active_habitations.where("valor_venda_cents > 0").sum(:valor_venda_cents).to_f / 100.0
    @avg_sale_value = active_habitations.where("valor_venda_cents > 0").average(:valor_venda_cents).to_f / 100.0
    @supply_demand_rows = supply_demand_rows(active_habitations)
  end

  def leads_time_series(days, scope = Lead)
    start_date = (days - 1).days.ago.to_date
    rows = scope
      .where("created_at >= ?", start_date.beginning_of_day)
      .group("DATE(created_at)")
      .count
    (0...days).map do |i|
      d = start_date + i
      [d, rows[d] || 0]
    end
  end

  def leads_hourly_series(date, scope = Lead)
    counts = scope
      .where(created_at: date.beginning_of_day...date.next_day.beginning_of_day)
      .pluck(:created_at)
      .each_with_object(Hash.new(0)) { |created_at, grouped| grouped[created_at.in_time_zone.hour] += 1 }

    (0..23).map { |hour| [format("%02dh", hour), counts[hour]] }
  end

  def selected_lead_date
    candidate = Date.iso8601(params[:lead_date].to_s)
    return candidate if candidate.between?(dashboard_window_start.to_date, Date.current)
  rescue Date::Error
    nil
  end

  def dashboard_window_start
    (@dashboard_period - 1).days.ago.to_date.beginning_of_day
  end

  def previous_dashboard_window
    current_start = dashboard_window_start
    (current_start - @dashboard_period.days)...current_start
  end

  def scoped_dashboard_habitations
    scope = current_tenant.habitations
    owner_ids = visible_owner_ids(:imoveis)
    scope = owner_ids.nil? ? scope : scope.where(admin_user_id: owner_ids)
    @dashboard_broker_id ? scope.where(admin_user_id: @dashboard_broker_id) : scope
  end

  def scoped_dashboard_leads
    scope = current_tenant.leads
    owner_ids = visible_owner_ids(:leads)
    scope = owner_ids.nil? ? scope : scope.where(admin_user_id: owner_ids)
    @dashboard_broker_id ? scope.where(admin_user_id: @dashboard_broker_id) : scope
  end

  def scoped_dashboard_captacoes
    scope = current_tenant.habitations.broker_intakes
    owner_ids = visible_owner_ids(:captacoes)
    scope = owner_ids.nil? ? scope : scope.where(admin_user_id: owner_ids)
    @dashboard_broker_id ? scope.where(admin_user_id: @dashboard_broker_id) : scope
  end

  def commercial_funnel_rows
    recent_scope = @lead_scope.where("created_at >= ?", dashboard_window_start)
    status_counts = recent_scope.group(:status).count
    total_leads = status_counts.values.sum

    discarded_status = Lead.status_value(:descartado)
    holding_status = Lead.status_value(:represado)
    in_service_status = Lead.status_value(:em_atendimento)
    waiting_status = Lead.status_value(:waiting_acceptance)
    closed_status = Lead.status_value(:concluido)

    interested_count = status_counts.reject { |status, _count| [discarded_status, holding_status].include?(Lead.status_value(status)) }.values.sum
    opportunity_count = status_counts.select { |status, _count| [in_service_status, waiting_status, closed_status].include?(Lead.status_value(status)) }.values.sum
    closed_count = status_counts[closed_status].to_i

    rows = [
      { label: "Clientes impactados", value: total_leads, benchmark: "10% a 20%", tone: "red" },
      { label: "Leads interessados", value: interested_count, benchmark: "5% a 15%", tone: "orange" },
      { label: "Oportunidades", value: opportunity_count, benchmark: "20% a 40%", tone: "amber" },
      { label: "Vendas", value: closed_count, benchmark: "0,1% a 1,2%", tone: "blue" }
    ]

    rows.each_cons(2) do |from, to|
      to[:conversion_rate] = percentage(to[:value], from[:value])
    end
    rows.last[:overall_conversion_rate] = percentage(closed_count, total_leads)
    rows
  end

  def catalog_quality_metrics
    publication_scope = @habitation_scope.publicly_listable
    scope = publication_scope.left_outer_joins(:address)
    without_address = scope.where(
      "NULLIF(TRIM(COALESCE(addresses.logradouro, habitations.endereco)), '') IS NULL"
    ).distinct.count
    without_price = scope.where(
      "COALESCE(habitations.valor_venda_cents, 0) <= 0 AND COALESCE(habitations.valor_locacao_cents, 0) <= 0"
    ).distinct.count
    without_photos = publication_scope.where.not(id: publication_scope.with_photos.select(:id)).count
    stale = scope.where(
      "COALESCE(habitations.data_atualizacao_crm, habitations.updated_at) < ?",
      90.days.ago
    ).distinct.count

    [
      { label: "Sem endereço", value: without_address, icon: "geo-alt", tone: "red", filter: "missing_address" },
      { label: "Sem fotos", value: without_photos, icon: "images", tone: "amber", filter: "missing_photos" },
      { label: "Sem preço", value: without_price, icon: "currency-dollar", tone: "red", filter: "missing_price" },
      { label: "Desatualizados há 90 dias", value: stale, icon: "clock-history", tone: "amber", filter: "stale" }
    ]
  end

  def percentage(value, total)
    return 0.0 if total.to_i.zero?

    ((value.to_f / total) * 100).round(1)
  end

  def percentage_change(current, previous)
    return nil if previous.to_i.zero?

    (((current.to_f - previous) / previous) * 100).round(1)
  end

  def broker_performance_rows
    counts = @lead_scope.where("leads.created_at >= ?", dashboard_window_start)
      .where.not(admin_user_id: nil).group(:admin_user_id).count
    closed_status = Lead.status_value(:concluido)
    closed_counts = @lead_scope.where("leads.created_at >= ?", dashboard_window_start)
      .where(status: closed_status).where.not(admin_user_id: nil).group(:admin_user_id).count
    names = current_tenant.admin_users.where(id: counts.keys).pluck(:id, :name).to_h

    counts.map do |broker_id, total|
      closed = closed_counts[broker_id].to_i
      { id: broker_id, name: names[broker_id] || "Corretor", total: total, closed: closed, conversion: percentage(closed, total) }
    end.sort_by { |row| [-row[:closed], -row[:total]] }.first(6)
  end

  def supply_demand_rows(active_habitations)
    supply = active_habitations.group(:categoria).count
    demand = @lead_scope.where("leads.created_at >= ?", dashboard_window_start)
      .where.not(property_id: nil)
      .joins("INNER JOIN habitations demand_habitations ON demand_habitations.id = leads.property_id AND demand_habitations.tenant_id = leads.tenant_id")
      .group("demand_habitations.categoria").count

    (supply.keys | demand.keys).map do |category|
      { category: category.presence || "Sem categoria", supply: supply[category].to_i, demand: demand[category].to_i }
    end.sort_by { |row| [-row[:demand], -row[:supply]] }.first(6)
  end
end
