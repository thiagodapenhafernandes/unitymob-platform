require "cgi"
require "zlib"

class Admin::DashboardController < Admin::BaseController
  include DeviceRequest

  DASHBOARD_SECTIONS = %w[charts acquisition funnel status service broker_performance campaign_performance rankings operations support site].freeze
  DASHBOARD_TABS = %w[leads overview properties site field].freeze
  DASHBOARD_PERIODS = [7, 14, 30, 90, 180].freeze
  DASHBOARD_PERIOD_PRESETS = %w[yesterday this_week this_month last_7 last_14 last_30 last_6_months custom].freeze
  DASHBOARD_BUSINESS_TYPES = %w[sale rental].freeze
  DASHBOARD_REPORT_SECTION_RESOURCES = {
    "broker_performance" => :dashboard_broker_performance,
    "campaign_performance" => :dashboard_campaign_performance
  }.freeze
  OVERVIEW_CACHE_EXPIRATION = 2.minutes
  DASHBOARD_AGGREGATE_CACHE_EXPIRATION = 5.minutes
  DASHBOARD_LEAD_FILTER_TEXT_SQL = <<~SQL.squish.freeze
    LOWER(CONCAT_WS(' ',
      leads.origin,
      leads.lead_type,
      leads.product,
      leads.notes,
      leads.status,
      leads.source_url,
      leads.other_information::text,
      leads.attribution_data::text
    ))
  SQL
  DASHBOARD_BUSINESS_FILTERS = {
    "sale" => "(#{DASHBOARD_LEAD_FILTER_TEXT_SQL} LIKE '%venda%' OR #{DASHBOARD_LEAD_FILTER_TEXT_SQL} LIKE '%compra%' OR #{DASHBOARD_LEAD_FILTER_TEXT_SQL} LIKE '%comprar%' OR #{DASHBOARD_LEAD_FILTER_TEXT_SQL} LIKE '%sale%')",
    "rental" => "(#{DASHBOARD_LEAD_FILTER_TEXT_SQL} LIKE '%loca%' OR #{DASHBOARD_LEAD_FILTER_TEXT_SQL} LIKE '%aluguel%' OR #{DASHBOARD_LEAD_FILTER_TEXT_SQL} LIKE '%alugar%' OR #{DASHBOARD_LEAD_FILTER_TEXT_SQL} LIKE '%rental%')"
  }.freeze
  CONTACT_ACTIVITY_KINDS = %w[
    accepted note whatsapp_out appointment_created appointment_done
    proposal_created proposal_sent proposal_viewed proposal_aceita proposal_recusada
  ].freeze
  DASHBOARD_REPORT_XLSX_MIME = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze
  DASHBOARD_REPORT_XLSX_COLUMN_WIDTHS = [26, 20, 20, 20, 42, 18, 18, 18].freeze

  before_action :require_dashboard_admin!
  before_action :set_dashboard_context

  def index
    load_overview_slice if @dashboard_tab == "overview"
  end

  def section
    section_name = params[:section].to_s
    raise ActiveRecord::RecordNotFound unless DASHBOARD_SECTIONS.include?(section_name)
    return head :forbidden unless dashboard_section_allowed?(section_name)

    unless turbo_frame_request?
      redirect_to admin_root_path(dashboard_section_redirect_params(section_name))
      return
    end

    @dashboard_tab = "all" if params[:tab].blank?
    send("load_#{section_name}_slice")
    render partial: "admin/dashboard/sections/#{section_name}", layout: false
  end

  def broker_performance_report
    return head :forbidden unless can_view_dashboard_report?(:dashboard_broker_performance)

    send_data broker_performance_report_xlsx,
              filename: "performance_corretores_#{@dashboard_start_date.iso8601}_#{@dashboard_end_date.iso8601}.xlsx",
              type: DASHBOARD_REPORT_XLSX_MIME
  end

  def campaign_performance_report
    return head :forbidden unless can_view_dashboard_report?(:dashboard_campaign_performance)

    send_data campaign_performance_report_xlsx,
              filename: "performance_campanhas_#{@dashboard_start_date.iso8601}_#{@dashboard_end_date.iso8601}.xlsx",
              type: DASHBOARD_REPORT_XLSX_MIME
  end

  private

  def dashboard_section_redirect_params(section_name)
    redirect_params = dashboard_date_params
    redirect_params[:tab] = section_name if DASHBOARD_TABS.include?(section_name)
    redirect_params[:tab] ||= params[:tab].to_s.presence_in(DASHBOARD_TABS)
    redirect_params[:broker_ids] = @dashboard_broker_ids if @dashboard_broker_ids.present?
    redirect_params
  end

  def require_dashboard_admin!
    return if tenant_owner? || can?(:view, :dashboard)
    return if desktop_device_request?

    redirect_to field_root_path
  end

  def set_dashboard_context
    @is_admin_view = tenant_owner?
    @can_view_broker_performance = can_view_dashboard_report?(:dashboard_broker_performance)
    @can_view_campaign_performance = can_view_dashboard_report?(:dashboard_campaign_performance)
    resolve_dashboard_period!
    @dashboard_broker_filter_owner_ids = dashboard_broker_filter_owner_ids
    @dashboard_brokers = dashboard_broker_filter_scope.order(:name).select(:id, :name)
    @dashboard_can_filter_brokers = @dashboard_broker_filter_owner_ids.nil? || @dashboard_brokers.size > 1
    @dashboard_broker_ids = resolve_dashboard_broker_ids
    @dashboard_broker_id = @dashboard_broker_ids.one? ? @dashboard_broker_ids.first : nil
    @dashboard_business_type = params[:business_type].to_s.presence_in(DASHBOARD_BUSINESS_TYPES)
    @habitation_scope = scoped_dashboard_habitations
    @lead_scope = scoped_dashboard_leads
    @captacao_scope = scoped_dashboard_captacoes
    @field_feature_enabled = FieldFeatureGate.field_checkin_enabled?(tenant: current_tenant)
    requested_tab = params[:tab].to_s.presence_in(DASHBOARD_TABS) || "leads"
    @dashboard_tab = requested_tab == "field" && !@field_feature_enabled ? "leads" : requested_tab
    @dashboard_updated_at = Time.current
    @dashboard_window_start = dashboard_window_start
    @dashboard_window_end = dashboard_window_end
    lead_setting = LeadSetting.instance(tenant: current_tenant)
    @first_contact_sla_hours = lead_setting.first_contact_sla_hours_value
    @first_contact_sla_label = lead_setting.first_contact_sla_duration_label
  end

  # Os ~18 counts do overview rodavam em TODA visita ao dashboard. KPIs de
  # visão geral toleram atraso curto — cache por conta+usuário (o escopo
  # visível depende do usuário). As seções (charts/funnel/...) seguem ao vivo.
  def load_overview_slice
    metrics = Rails.cache.fetch(
      ["dashboard-overview-v7", current_tenant.id, current_admin_user.id, @dashboard_period, @dashboard_broker_ids, @dashboard_business_type],
      expires_in: OVERVIEW_CACHE_EXPIRATION
    ) { compute_overview_metrics }
    metrics.each { |name, value| instance_variable_set("@#{name}", value) }
    @operational_questions = build_operational_questions
    @decision_questions = @operational_questions.select { |question| question[:attention] }
    @health_questions = @operational_questions.reject { |question| question[:attention] }
    @overview_investigations = build_overview_investigations
    @recommended_actions = build_recommended_actions
    @dashboard_tab_badges = build_dashboard_tab_badges
  end

  def compute_overview_metrics
    active_habitations = @habitation_scope.active
    valid_leads = valid_dashboard_leads_scope
    beginning = Date.current.beginning_of_day

    @properties_count = active_habitations.count
    @featured_count = active_habitations.featured.count
    @developments_count = scoped_dashboard_catalog_habitations.empreendimentos.count

    @brokers_active = @is_admin_view ? current_tenant.admin_users.active.count : 0
    @stores_active_count = @is_admin_view ? current_tenant.stores.active.count : 0
    @active_checkins_count = @is_admin_view ? CheckIn.where(tenant: current_tenant, status: :active).count : (current_admin_user.active_check_in.present? ? 1 : 0)
    @today_checkins_count = @is_admin_view ? CheckIn.where(tenant: current_tenant).today.count : CheckIn.where(tenant: current_tenant, admin_user_id: current_admin_user.id).today.count
    @suspicious_checkins = @is_admin_view ? CheckIn.where(tenant: current_tenant, suspicious: true).count : 0
    @pending_manual_requests = @is_admin_view ? ManualCheckinRequest.where(tenant: current_tenant).pending.count : 0

    @leads_total = valid_leads.count
    @new_leads = valid_leads.where(status: [Lead.default_status, nil]).count
    @leads_today = valid_leads.where("leads.created_at >= ?", beginning).count
    @leads_last_7_days = valid_leads.where("leads.created_at >= ?", 7.days.ago).count
    @current_period_leads = valid_leads.where("leads.created_at >= ?", dashboard_window_start).count
    @previous_period_leads = valid_leads.where(created_at: previous_dashboard_window).count
    @leads_period_change = percentage_change(@current_period_leads, @previous_period_leads)
    @holding_leads = @is_admin_view ? @lead_scope.holding.count : 0
    active_lead_statuses_with_blank = active_lead_status_values_with_blank
    @unassigned_open_leads = @lead_scope.where(admin_user_id: nil, status: active_lead_statuses_with_blank).count
    @stalled_open_leads = @lead_scope.where(status: active_lead_statuses_with_blank).where("leads.updated_at < ?", 2.days.ago).count
    @lead_open_tasks = dashboard_task_scope.pendentes.count
    @lead_overdue_tasks = dashboard_task_scope.atrasadas.count
    @lead_tasks_due_today = dashboard_task_scope.hoje.count
    @lead_tasks_week = dashboard_task_scope.semana.count
    @attention_open_leads = @lead_scope
      .where(status: active_lead_statuses_with_blank)
      .then { |scope| attention_leads(scope) }
      .count
    @no_first_contact_leads = no_first_contact_scope.count
    @sla_overdue_leads = no_first_contact_scope.where("leads.created_at < ?", first_contact_sla_hours.hours.ago).count
    @avg_first_contact_minutes = average_first_contact_minutes
    @pending_whatsapp_conversations = pending_whatsapp_reply_scope.count
    @avg_whatsapp_response_minutes = average_whatsapp_response_minutes

    @distribution_rules_total = @is_admin_view ? current_tenant.distribution_rules.count : 0
    @distribution_rules_active = @is_admin_view ? current_tenant.distribution_rules.active.count : 0
    @rules_with_checkin = @is_admin_view ? current_tenant.distribution_rules.where(require_active_checkin: true).count : 0

    @sync_errors_count = @is_admin_view ? scoped_dashboard_catalog_habitations.where(last_sync_status: "error").count : 0
    @today_captacoes = @captacao_scope.where(habitations: { created_at: beginning.. }).count
    @today_new_habitations = scoped_dashboard_catalog_habitations.where("COALESCE(habitations.data_atualizacao_crm, habitations.created_at) >= ?", beginning).count
    draft_captacoes = @captacao_scope.where(intake_status: [nil, "draft"])
    @drafts_count = draft_captacoes.count
    @stale_drafts_count = draft_captacoes.where("habitations.updated_at < ?", 30.days.ago).count
    @oldest_draft_updated_at = draft_captacoes.minimum("habitations.updated_at")

    %i[properties_count featured_count developments_count brokers_active stores_active_count
       active_checkins_count today_checkins_count suspicious_checkins pending_manual_requests
       leads_total new_leads leads_today leads_last_7_days holding_leads
       current_period_leads previous_period_leads unassigned_open_leads stalled_open_leads attention_open_leads
       lead_open_tasks lead_overdue_tasks lead_tasks_due_today lead_tasks_week
       no_first_contact_leads sla_overdue_leads avg_first_contact_minutes pending_whatsapp_conversations avg_whatsapp_response_minutes
       distribution_rules_total distribution_rules_active rules_with_checkin
       sync_errors_count today_captacoes today_new_habitations drafts_count
       stale_drafts_count oldest_draft_updated_at leads_period_change]
      .index_with { |name| instance_variable_get("@#{name}") }
  end

  def load_charts_slice
    chart_scope = valid_dashboard_leads_scope.where(created_at: dashboard_window_start..dashboard_window_end)
    @leads_by_status = chart_scope.group(:status).count
    @leads_series = leads_time_series(@dashboard_start_date, @dashboard_end_date, chart_scope)
    @leads_total = chart_scope.count
    @leads_chart_mode = "daily"
    lead_drilldown_filter = @dashboard_broker_id.present? ? { broker_id: @dashboard_broker_id } : {}
    @leads_drilldown_urls = @leads_series.map { |date, _| admin_leads_path(lead_drilldown_filter.merge(start_date: date.iso8601, end_date: date.iso8601)) }
  end

  def load_acquisition_slice
    result = lead_acquisition_result
    result.each { |name, value| instance_variable_set("@acquisition_#{name}", value) }
    @lost_money_rows = lost_money_rows
  end

  def load_funnel_slice
    @commercial_funnel_rows = commercial_funnel_rows
    @stage_loss_rows = stage_loss_rows
    @lead_temperature_rows = lead_temperature_rows
    @stage_reopen_rows = stage_reopen_rows
  end

  def load_status_slice
    @leads_by_status = valid_dashboard_leads_scope.where(created_at: dashboard_window_start..dashboard_window_end).group(:status).count
    @lead_status_rows = @leads_by_status.map do |status, count|
      canonical_status = Lead.status_value(status.presence || Lead.default_status)
      {
        label: canonical_status,
        count: count,
        path: admin_leads_path(
          status: canonical_status,
          start_date: dashboard_window_start.to_date.iso8601,
          end_date: @dashboard_end_date.iso8601
        )
      }
    end.sort_by { |row| -row[:count] }
  end

  def load_service_slice
    load_service_sla_metrics
    @service_sla_rows = service_sla_rows
  end

  def load_campaign_performance_slice
    @campaign_performance = campaign_performance_result.rows
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

  def load_broker_performance_slice
    @broker_performance = @can_view_broker_performance ? broker_performance_rows : []
  end

  def load_operations_slice
    @bs_to_ax = { "success" => "green", "danger" => "red", "warning" => "amber", "info" => "blue", "primary" => "blue", "secondary" => "gray", "dark" => "gray" }
    @recent_audit_logs = if @is_admin_view
                           current_tenant.checkin_audit_logs.includes(:admin_user, :actor_admin_user, check_in: :store).order(created_at: :desc).limit(6)
                         else
                           current_tenant.checkin_audit_logs.includes(:actor_admin_user, check_in: :store).where(admin_user_id: current_admin_user.id).order(created_at: :desc).limit(6)
                         end
    @recent_habitations = scoped_dashboard_catalog_habitations
      .includes(:address)
      .where.not(data_atualizacao_crm: nil)
      .order(data_atualizacao_crm: :desc)
      .limit(6)
    @catalog_quality_metrics = catalog_quality_metrics
    @property_low_progress_rows = property_low_progress_rows
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

  def load_site_slice
    site_events = scoped_public_navigation_events.where("public_navigation_events.occurred_at >= ?", dashboard_window_start)
    @site_kpis = {
      visits: site_events.where(name: "page_view").count,
      property_views: site_events.where(name: "property_view").count,
      searches: site_events.where(name: "property_search").count,
      no_results: site_events.where(name: "search_no_results").count,
      whatsapp_clicks: site_events.where(name: "property_whatsapp_click").count,
      phone_clicks: site_events.where(name: "property_phone_click").count,
      form_submissions: site_events.where(name: "lead_form_submitted").count
    }
    @site_top_pages = site_top_pages(site_events)
    @site_top_properties = site_top_properties(site_events)
    @site_search_filters = site_search_filters(site_events)
    @site_conversion_funnel = site_conversion_funnel(site_events)
    @site_home_section_clicks = site_home_section_clicks(site_events)
  end

  def leads_time_series(start_date, end_date, scope = Lead)
    rows = scope
      .where(created_at: start_date.beginning_of_day..end_date.end_of_day)
      .group("DATE(created_at)")
      .count
    (0...((end_date - start_date).to_i + 1)).map do |i|
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

  def dashboard_window_start
    @dashboard_start_date.beginning_of_day
  end

  def dashboard_window_end
    @dashboard_end_date.end_of_day
  end

  def first_contact_sla_hours
    @first_contact_sla_hours || LeadSetting::DEFAULT_FIRST_CONTACT_SLA_HOURS
  end

  def previous_dashboard_window
    current_start = dashboard_window_start
    (current_start - @dashboard_period.days)...current_start
  end

  def resolve_dashboard_period!
    today = Date.current
    preset = params[:period_preset].to_s.presence_in(DASHBOARD_PERIOD_PRESETS)
    start_date = parse_dashboard_date(params[:start_date])
    end_date = parse_dashboard_date(params[:end_date])

    if start_date && end_date
      preset ||= "custom"
    else
      preset ||= "last_#{params[:period].to_i}" if params[:period].to_i.presence_in(DASHBOARD_PERIODS)
      preset ||= "last_7"
      start_date, end_date = dashboard_preset_range(preset, today)
    end

    start_date, end_date = end_date, start_date if start_date > end_date
    @dashboard_period_preset = preset
    @dashboard_start_date = start_date
    @dashboard_end_date = end_date
    @dashboard_period = (end_date - start_date).to_i + 1
    @dashboard_period_label = "#{I18n.l(start_date, format: :short)} – #{I18n.l(end_date, format: :short)}"
  end

  def dashboard_preset_range(preset, today)
    case preset
    when "yesterday" then [today.yesterday, today.yesterday]
    when "this_week" then [today.beginning_of_week, today]
    when "this_month" then [today.beginning_of_month, today]
    when "last_7" then [today - 6.days, today]
    when "last_14" then [today - 13.days, today]
    when "last_6_months" then [today - 6.months + 1.day, today]
    else [today - 29.days, today]
    end
  end

  def parse_dashboard_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end

  def dashboard_date_params(extra = {})
    params = {
      period_preset: @dashboard_period_preset,
      start_date: @dashboard_start_date.iso8601,
      end_date: @dashboard_end_date.iso8601
    }
    params[:business_type] = @dashboard_business_type if @dashboard_business_type.present?
    params[:broker_ids] = @dashboard_broker_ids if @dashboard_broker_ids.present?
    params.merge(extra).compact_blank
  end

  def resolve_dashboard_broker_ids
    return [] unless @dashboard_can_filter_brokers

    ids = Array(params[:broker_ids]).flat_map { |value| value.to_s.split(",") }
    ids << params[:broker_id] if ids.blank? && params[:broker_id].present?
    ids = ids.filter_map { |value| Integer(value, exception: false) }.uniq
    return [] if ids.blank?

    allowed_ids = @dashboard_brokers.map(&:id)
    ids & allowed_ids
  end

  def dashboard_section_allowed?(section_name)
    resource = DASHBOARD_REPORT_SECTION_RESOURCES[section_name]
    return true if resource.blank?

    can_view_dashboard_report?(resource)
  end

  def can_view_dashboard_report?(resource)
    can?(:view, resource)
  end

  def dashboard_broker_filter_resources
    resources = [:leads]
    resources << :dashboard_broker_performance if can_view_dashboard_report?(:dashboard_broker_performance)
    resources << :dashboard_campaign_performance if can_view_dashboard_report?(:dashboard_campaign_performance)
    resources.select { |resource| can?(:view, resource) }
  end

  def dashboard_broker_filter_owner_ids
    return nil if tenant_owner?

    resources = dashboard_broker_filter_resources
    return [current_admin_user.id] if resources.blank?
    return nil if resources.any? { |resource| owns_all_resource?(resource) }

    resources.flat_map do |resource|
      current_admin_user&.can_view_team?(resource) ? team_scope_ids : [current_admin_user&.id].compact
    end.uniq
  end

  def dashboard_broker_filter_scope
    scope = current_tenant.admin_users.active
    @dashboard_broker_filter_owner_ids.nil? ? scope : scope.where(id: @dashboard_broker_filter_owner_ids)
  end

  def scoped_dashboard_habitations
    scope = current_tenant.habitations
    owner_ids = visible_owner_ids(:imoveis)
    scope = owner_ids.nil? ? scope : scope.where(admin_user_id: owner_ids)
    scope = scope.where(admin_user_id: @dashboard_broker_ids) if @dashboard_broker_ids.present?
    apply_dashboard_habitation_business_filter(scope)
  end

  def scoped_dashboard_catalog_habitations
    scoped_dashboard_habitations.commercially_publishable.where(
      "habitations.intake_origin IS NULL OR habitations.intake_origin != :broker_origin OR habitations.intake_status IN (:visible_statuses)",
      broker_origin: Habitation::INTAKE_ORIGIN_BROKER,
      visible_statuses: Habitation::CATALOG_VISIBLE_INTAKE_STATUSES
    )
  end

  def scoped_dashboard_leads
    scope = current_tenant.leads
    owner_ids = visible_owner_ids(:leads)
    scope = owner_ids.nil? ? scope : scope.where(admin_user_id: owner_ids)
    scope = scope.where(admin_user_id: @dashboard_broker_ids) if @dashboard_broker_ids.present?
    scope = apply_dashboard_lead_business_filter(scope)
    exclude_internal_contact_leads(scope)
  end

  def valid_dashboard_leads_scope(scope = @lead_scope)
    invalid_statuses = invalid_operational_lead_status_values
    return scope if invalid_statuses.empty?

    scope.where("leads.status IS NULL OR leads.status NOT IN (?)", invalid_statuses)
  end

  def scoped_dashboard_report_leads(resource)
    scope = current_tenant.leads
    owner_ids = visible_owner_ids(resource)
    scope = owner_ids.nil? ? scope : scope.where(admin_user_id: owner_ids)
    scope = scope.where(admin_user_id: @dashboard_broker_ids) if @dashboard_broker_ids.present?
    scope = apply_dashboard_lead_business_filter(scope)
    exclude_internal_contact_leads(scope)
  end

  def active_dashboard_leads_scope
    @lead_scope.where(status: active_lead_status_values_with_blank)
  end

  def dashboard_task_scope
    current_tenant.tasks
      .operational_current
      .where(lead_id: active_dashboard_leads_scope.select(:id))
  end

  def scoped_dashboard_captacoes
    scope = current_tenant.habitations.broker_intakes
    owner_ids = visible_owner_ids(:captacoes)
    scope = owner_ids.nil? ? scope : scope.where(admin_user_id: owner_ids)
    scope = scope.where(admin_user_id: @dashboard_broker_ids) if @dashboard_broker_ids.present?
    apply_dashboard_habitation_business_filter(scope)
  end

  def apply_dashboard_habitation_business_filter(scope)
    case @dashboard_business_type
    when "sale"
      scope.where("COALESCE(habitations.valor_venda_cents, 0) > 0 OR habitations.status ILIKE ?", "%venda%")
    when "rental"
      scope.where("COALESCE(habitations.valor_locacao_cents, 0) > 0 OR habitations.status ILIKE ? OR habitations.status ILIKE ?", "%aluguel%", "%loca%")
    else
      scope
    end
  end

  def apply_dashboard_lead_business_filter(scope)
    return scope if @dashboard_business_type.blank?

    scope = scope.joins("LEFT OUTER JOIN habitations ON habitations.id = leads.property_id AND habitations.tenant_id = leads.tenant_id")
    case @dashboard_business_type
    when "sale"
      scope.where("(COALESCE(habitations.valor_venda_cents, 0) > 0 OR #{DASHBOARD_BUSINESS_FILTERS.fetch("sale")})")
    when "rental"
      scope.where("(COALESCE(habitations.valor_locacao_cents, 0) > 0 OR #{DASHBOARD_BUSINESS_FILTERS.fetch("rental")})")
    else
      scope
    end
  end

  def exclude_internal_contact_leads(scope)
    phones = internal_contact_phones
    return scope if phones.empty?

    scope.where.not(
      "regexp_replace(coalesce(leads.phone, ''), '\\D', '', 'g') IN (:phones) OR regexp_replace(coalesce(leads.client_phone, ''), '\\D', '', 'g') IN (:phones)",
      phones: phones
    )
  end

  def internal_contact_phones
    @internal_contact_phones ||= current_tenant.admin_users
      .account_members
      .pluck(:phone, :secondary_phone)
      .flatten
      .filter_map { |phone| Phones::Normalizer.call(phone).to_s.presence }
      .uniq
  end

  def commercial_funnel_rows
    recent_scope = valid_dashboard_leads_scope.where("leads.created_at >= ?", dashboard_window_start)
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

  def lost_money_rows
    @lost_money_rows ||= begin
      period_scope = @lead_scope.where("leads.created_at >= ?", dashboard_window_start)
      paid_scope = period_scope.where(attribution_channel: Dashboard::LeadAcquisitionQuery::PAID_CHANNELS)
      paid_without_contact = paid_scope
        .where(status: active_lead_status_values_with_blank)
        .where.not(id: human_contact_activity_scope.select(:lead_id))
      channel_quality = @acquisition_channel_quality || []
      weak_paid_channel = channel_quality
        .select { |row| row[:key].to_s.in?(Dashboard::LeadAcquisitionQuery::PAID_CHANNELS) }
        .sort_by { |row| [row[:opportunity_rate].to_f, -row[:total].to_i] }
        .first
      expensive_paid_channel = expensive_paid_channel_row(channel_quality)
      weak_campaign = current_tenant.marketing_campaigns
        .where("budget_cents > 0")
        .where("starts_on IS NULL OR starts_on <= ?", Date.current)
        .where("ends_on IS NULL OR ends_on >= ?", dashboard_window_start.to_date)
        .to_a
        .sort_by { |campaign| [campaign.conversions_count.to_i.zero? ? 0 : 1, -campaign.budget_cents.to_i, campaign.cost_per_conversion] }
        .first
      property_row = property_low_progress_rows.first

      rows = [
        {
          label: "Leads pagos sem atendimento",
          value: paid_without_contact.count,
          detail: "Meta/Google/Microsoft sem primeiro contato registrado",
          tone: paid_without_contact.exists? ? "red" : "green",
          path: admin_leads_path(attention_filter: "no_first_contact", start_date: dashboard_window_start.to_date.iso8601, end_date: @dashboard_end_date.iso8601)
        }
      ]

      if expensive_paid_channel
        rows << expensive_paid_channel
      elsif weak_paid_channel
        rows << {
          label: "Canal pago com baixa evolução",
          value: weak_paid_channel[:total],
          detail: "#{weak_paid_channel[:label]} com #{weak_paid_channel[:opportunity_rate]}% de avanço",
          tone: weak_paid_channel[:opportunity_rate].to_f < 10 ? "red" : "amber",
          path: admin_leads_path(attribution_channel: weak_paid_channel[:key], start_date: dashboard_window_start.to_date.iso8601, end_date: @dashboard_end_date.iso8601)
        }
      end

      if weak_campaign
        rows << {
          label: "Campanha com custo e pouco retorno",
          value: weak_campaign.conversions_count.to_i,
          detail: "#{weak_campaign.name}: #{formatted_currency(weak_campaign.budget)} investidos",
          tone: weak_campaign.conversions_count.to_i.zero? ? "red" : "amber",
          path: edit_admin_marketing_campaign_path(weak_campaign)
        }
      end

      rows << property_row.merge(label: "Imóvel com interesse sem evolução") if property_row
      rows
    end
  end

  def expensive_paid_channel_row(channel_quality)
    campaign_rows = current_tenant.marketing_campaigns
      .where(channel: Dashboard::LeadAcquisitionQuery::PAID_CHANNELS)
      .where("budget_cents > 0")
      .where("starts_on IS NULL OR starts_on <= ?", Date.current)
      .where("ends_on IS NULL OR ends_on >= ?", dashboard_window_start.to_date)
      .group(:channel)
      .pluck(:channel, Arel.sql("SUM(budget_cents)"), Arel.sql("SUM(conversions_count)"), Arel.sql("SUM(clicks_count)"))

    return nil if campaign_rows.empty?

    quality_by_channel = channel_quality.index_by { |row| row[:key].to_s }
    row = campaign_rows
      .map do |channel, budget_cents, conversions_count, clicks_count|
        conversions = conversions_count.to_i
        budget = budget_cents.to_i
        quality = quality_by_channel[channel] || {}
        cost_per_conversion_cents = conversions.positive? ? (budget.to_f / conversions).round : budget
        conversion_rate = clicks_count.to_i.positive? ? ((conversions.to_f / clicks_count.to_i) * 100).round(1) : 0.0
        {
          channel: channel,
          budget_cents: budget,
          conversions: conversions,
          conversion_rate: conversion_rate,
          opportunity_rate: quality[:opportunity_rate].to_f,
          cost_per_conversion_cents: cost_per_conversion_cents,
          score: [conversions.zero? ? 0 : 1, -cost_per_conversion_cents, quality[:opportunity_rate].to_f]
        }
      end
      .sort_by { |item| item[:score] }
      .first

    return nil unless row

    label = Dashboard::LeadAcquisitionQuery::CHANNEL_LABELS.fetch(row[:channel], row[:channel].to_s.humanize)
    {
      label: "Canal caro com baixa conversão",
      value: row[:conversions],
      detail: "#{label}: #{formatted_currency(row[:budget_cents].to_i / 100.0)} investidos, #{row[:conversion_rate]}% de conversão e #{row[:opportunity_rate]}% de avanço",
      tone: row[:conversions].zero? || row[:opportunity_rate] < 10 ? "red" : "amber",
      path: admin_marketing_campaigns_path(channel: row[:channel])
    }
  end

  def stage_time_rows
    @stage_time_rows ||= begin
      scope = @lead_scope
        .where(status: active_lead_status_values_with_blank)
        .where("leads.created_at >= ? OR leads.updated_at >= ?", dashboard_window_start, dashboard_window_start)
      leads = scope.pluck(:id, :status, :created_at)
      if leads.empty?
        []
      else
        last_status_changes = current_tenant.lead_audit_logs
          .where(lead_id: leads.map(&:first), action: "status_changed")
          .group(:lead_id)
          .maximum(:created_at)

        grouped = Hash.new { |hash, key| hash[key] = { total_hours: 0.0, count: 0 } }
        leads.each do |lead_id, status, created_at|
          label = Lead.status_value(status.presence || Lead.default_status(tenant: current_tenant), tenant: current_tenant)
          entered_at = [last_status_changes[lead_id] || created_at, Time.current].compact.min
          hours = ((Time.current - entered_at) / 1.hour).round(1)
          grouped[label][:total_hours] += hours
          grouped[label][:count] += 1
        end

        grouped.map do |label, values|
          average_hours = values[:count].zero? ? 0 : (values[:total_hours] / values[:count]).round(1)
          {
            label: label,
            value: average_hours,
            detail: "#{values[:count]} lead(s) abertos nesta etapa",
            tone: average_hours > 48 ? "amber" : "blue",
            path: admin_leads_path(status: label)
          }
        end.sort_by { |row| [-row[:value].to_f, row[:label].to_s] }.first(6)
      end
    end
  end

  def stage_loss_rows
    @stage_loss_rows ||= begin
      lost_statuses = lost_lead_status_values
      rows = lead_status_change_logs.filter_map do |changeset|
        status_change = changeset.to_h["status"].to_h
        from = Lead.status_value(status_change["before"].to_s, tenant: current_tenant)
        to = Lead.status_value(status_change["after"].to_s, tenant: current_tenant)
        next unless lost_statuses.include?(to)

        from.presence || "Sem etapa anterior"
      end.tally

      rows.map do |label, count|
        {
          label: label,
          value: count,
          detail: "oportunidade perdida a partir desta etapa",
          tone: "red",
          path: admin_leads_path(status: label)
        }
      end.sort_by { |row| [-row[:value].to_i, row[:label].to_s] }.first(6)
    end
  end

  def lead_temperature_rows
    @lead_temperature_rows ||= [
      temperature_row("Leads quentes sem ação", "quente", 1.day.ago, "red"),
      temperature_row("Leads mornos sem ação", "morno", 3.days.ago, "amber")
    ]
  end

  def stage_reopen_rows
    @stage_reopen_rows ||= begin
      open_statuses = active_lead_status_values
      terminal_statuses = terminal_lead_status_values
      rows = lead_status_change_logs.filter_map do |changeset|
        status_change = changeset.to_h["status"].to_h
        from = Lead.status_value(status_change["before"].to_s, tenant: current_tenant)
        to = Lead.status_value(status_change["after"].to_s, tenant: current_tenant)
        next unless terminal_statuses.include?(from) && open_statuses.include?(to)

        to
      end.tally

      rows.map do |label, count|
        {
          label: label,
          value: count,
          detail: "voltas de etapa no período",
          tone: count.positive? ? "amber" : "green",
          path: admin_leads_path(status: label)
        }
      end.sort_by { |row| [-row[:value].to_i, row[:label].to_s] }.first(6)
    end
  end

  def catalog_quality_metrics
    @catalog_quality_metrics ||= Rails.cache.fetch(
      ["dashboard-catalog-quality-v2", current_tenant.id],
      expires_in: DASHBOARD_AGGREGATE_CACHE_EXPIRATION
    ) { compute_catalog_quality_metrics }
  end

  def compute_catalog_quality_metrics
    catalog_scope = scoped_dashboard_catalog_habitations
    publication_scope = catalog_scope.publicly_listable
    scope = publication_scope.left_outer_joins(:address)
    without_address = scope.where(
      "NULLIF(TRIM(COALESCE(addresses.logradouro, habitations.endereco)), '') IS NULL"
    ).distinct.count
    without_price = catalog_scope.without_operational_price.distinct.count
    missing_price_developments = catalog_scope
      .where("COALESCE(habitations.valor_venda_cents, 0) <= 0 AND COALESCE(habitations.valor_locacao_cents, 0) <= 0")
      .where("COALESCE(habitations.tipo, '') = ?", "Empreendimento")
      .distinct
      .count
    without_photos = catalog_scope.where.not(id: Habitation.with_photos.select(:id)).distinct.count
    stale = scope.where(
      "COALESCE(habitations.data_atualizacao_crm, habitations.updated_at) < ?",
      90.days.ago
    ).distinct.count

    [
      { label: "Sem endereço", value: without_address, icon: "geo-alt", tone: "red", filter: "missing_address" },
      { label: "Sem fotos", value: without_photos, icon: "images", tone: "amber", filter: "missing_photos" },
      {
        label: "Sem preço",
        value: without_price,
        icon: "currency-dollar",
        tone: "red",
        filter: "missing_price",
        detail: "Sem valor de venda/locação; #{missing_price_developments} empreendimento(s) fora do alerta."
      },
      { label: "Desatualizados há 90 dias", value: stale, icon: "clock-history", tone: "amber", filter: "stale" }
    ]
  end

  def build_dashboard_tab_badges
    quality_metrics = catalog_quality_metrics.index_by { |metric| metric[:filter] }
    missing_price_count = quality_metrics.fetch("missing_price", {})[:value].to_i
    stale_count = quality_metrics.fetch("stale", {})[:value].to_i

    {
      "leads" => [
        {
          label: "Total",
          value: @leads_total,
          tone: "blue",
          title: "Total geral de leads visíveis no escopo atual do dashboard."
        },
        {
          label: "Sem resp.",
          value: @unassigned_open_leads,
          tone: @unassigned_open_leads.to_i.positive? ? "red" : "green",
          title: "Leads abertos que ainda não têm corretor responsável."
        },
        {
          label: "Tarefas",
          value: @lead_overdue_tasks,
          tone: @lead_overdue_tasks.to_i.positive? ? "red" : "green",
          title: "Tarefas vencidas em leads abertos do escopo atual."
        },
        {
          label: "SLA",
          value: @sla_overdue_leads,
          tone: @sla_overdue_leads.to_i.positive? ? "red" : "green",
          title: "Leads sem registro de primeiro contato há mais de #{first_contact_sla_hours} horas."
        }
      ],
      "properties" => [
        {
          label: "Ativos",
          value: @properties_count,
          tone: "blue",
          title: "Total geral de imóveis ativos visíveis no escopo atual do dashboard."
        },
        {
          label: "Sem preço",
          value: missing_price_count,
          tone: missing_price_count.positive? ? "red" : "green",
          title: "Imóveis do catálogo operacional sem preço de venda e locação, excluindo empreendimentos."
        },
        {
          label: "90d+",
          value: stale_count,
          tone: stale_count.positive? ? "amber" : "green",
          title: "Imóveis publicáveis sem atualização há mais de 90 dias."
        }
      ],
      "site" => [
        {
          label: "Visitas",
          value: site_event_badge_counts["page_view"].to_i,
          tone: "blue",
          title: "Páginas públicas vistas no período, geradas pelo rastreamento próprio do site."
        },
        {
          label: "Imóveis vistos",
          value: site_event_badge_counts["property_view"].to_i,
          tone: "blue",
          title: "Aberturas reais de páginas de imóveis no site público."
        },
        {
          label: "WhatsApp",
          value: site_event_badge_counts["property_whatsapp_click"].to_i,
          tone: "green",
          title: "Cliques reais em chamadas de WhatsApp capturados no site público."
        }
      ]
    }
  end

  def build_operational_questions
    [
      lead_response_question,
      catalog_readiness_question,
      demand_generation_question,
      intake_flow_question,
      distribution_question
    ].compact.sort_by { |question| question[:priority] }
  end

  def build_overview_investigations
    [
      broker_attention_investigation,
      service_level_investigation,
      whatsapp_attention_investigation,
      funnel_bottleneck_investigation,
      property_attention_investigation,
      catalog_bottleneck_investigation,
      demand_channel_investigation
    ].compact
  end

  def build_recommended_actions
    actions = []
    actions << recommended_action(
      title: "Resolver tarefas vencidas",
      detail: "#{@lead_overdue_tasks} tarefa(s) pendente(s) passaram do prazo.",
      value: @lead_overdue_tasks,
      tone: "red",
      icon: "alarm",
      path: admin_leads_path(attention_filter: "task_overdue")
    ) if @lead_overdue_tasks.to_i.positive?

    actions << recommended_action(
      title: "Executar tarefas de hoje",
      detail: "#{@lead_tasks_due_today} tarefa(s) vencem hoje em leads ativos.",
      value: @lead_tasks_due_today,
      tone: "amber",
      icon: "calendar-check",
      path: admin_leads_path(attention_filter: "task_due_today")
    ) if @lead_tasks_due_today.to_i.positive?

    actions << recommended_action(
      title: "Atender leads sem primeiro contato",
      detail: "#{@sla_overdue_leads} já passaram de #{first_contact_sla_hours}h sem registro de atendimento.",
      value: @no_first_contact_leads,
      tone: @sla_overdue_leads.to_i.positive? ? "red" : "amber",
      icon: "telephone-outbound",
      path: admin_leads_path(attention_filter: "no_first_contact")
    ) if @no_first_contact_leads.to_i.positive?

    actions << recommended_action(
      title: "Responder WhatsApp pendente",
      detail: "#{@pending_whatsapp_conversations} conversa(s) aberta(s) com cliente aguardando retorno.",
      value: @pending_whatsapp_conversations,
      tone: "red",
      icon: "whatsapp",
      path: admin_whatsapp_conversations_path(filter: "pending_reply")
    ) if @pending_whatsapp_conversations.to_i.positive?

    actions << recommended_action(
      title: "Organizar leads sem dono",
      detail: "#{@unassigned_open_leads} lead(s) abertos ainda não têm corretor responsável.",
      value: @unassigned_open_leads,
      tone: "red",
      icon: "person-exclamation",
      path: admin_leads_path(attention_filter: "requires_action")
    ) if @unassigned_open_leads.to_i.positive?

    catalog_quality_metrics
      .select { |metric| metric[:value].to_i.positive? }
      .sort_by { |metric| -metric[:value].to_i }
      .first(3)
      .each do |metric|
        actions << recommended_action(
          title: "Corrigir #{metric[:label].downcase} no catálogo",
          detail: metric[:detail].presence || "Abrir imóveis filtrados para revisão.",
          value: metric[:value],
          tone: metric[:tone],
          icon: metric[:icon],
          path: admin_habitations_path(metric[:path_params].presence || { ownership: "all", dashboard_quality: metric[:filter] })
        )
      end

    acquisition = lead_acquisition_result
    if acquisition[:unknown].to_i.positive?
      actions << recommended_action(
        title: "Corrigir origem dos leads",
        detail: "#{acquisition[:unknown]} lead(s) chegaram como Direto/desconhecido.",
        value: acquisition[:unknown],
        tone: "amber",
        icon: "signpost-split",
        path: admin_leads_path(
          attribution_channel: "direct",
          start_date: dashboard_window_start.to_date.iso8601,
          end_date: @dashboard_end_date.iso8601,
          broker_id: @dashboard_broker_id
        )
      )
    end

    actions.sort_by { |action| [action[:priority], -action[:value].to_i] }.first(6)
  end

  def recommended_action(title:, detail:, value:, tone:, icon:, path:)
    {
      title: title,
      detail: detail,
      value: value,
      tone: tone,
      icon: icon,
      path: path,
      priority: { "red" => 10, "amber" => 20, "blue" => 30, "green" => 40 }.fetch(tone.to_s, 30)
    }
  end

  def broker_attention_investigation
    rows = broker_attention_rows
    {
      question: "Quem está segurando atendimento?",
      answer: rows.any? ? "Responsáveis com maior volume de ações pendentes." : "Nenhum corretor com lead aberto em atenção.",
      tone: rows.any? ? "red" : "green",
      icon: "person-lines-fill",
      path: admin_leads_path,
      rows: rows,
      empty: "Sem leads travados por responsável."
    }
  end

  def service_level_investigation
    rows = [
      {
        label: "Tarefas vencidas",
        value: @lead_overdue_tasks,
        detail: "Tarefas pendentes passaram do prazo dentro dos leads",
        tone: @lead_overdue_tasks.to_i.positive? ? "red" : "green",
        path: admin_leads_path(attention_filter: "task_overdue")
      },
      {
        label: "Tarefas de hoje",
        value: @lead_tasks_due_today,
        detail: "Tarefas que vencem hoje dentro dos leads",
        tone: @lead_tasks_due_today.to_i.positive? ? "amber" : "green",
        path: admin_leads_path(attention_filter: "task_due_today")
      },
      {
        label: "Sem primeiro contato",
        value: @no_first_contact_leads,
        detail: "Leads sem registro de atendimento no histórico",
        tone: @no_first_contact_leads.to_i.positive? ? "red" : "green",
        path: admin_leads_path(attention_filter: "no_first_contact")
      },
      {
        label: "SLA #{first_contact_sla_hours}h vencido",
        value: @sla_overdue_leads,
        detail: "Entraram há mais de #{first_contact_sla_hours}h e seguem sem contato",
        tone: @sla_overdue_leads.to_i.positive? ? "red" : "green",
        path: admin_leads_path(attention_filter: "sla_overdue")
      },
      {
        label: "Tempo médio até contato",
        value: @avg_first_contact_minutes,
        detail: @avg_first_contact_minutes.to_i.positive? ? "minutos nos leads com atendimento registrado" : "sem base suficiente no período",
        tone: @avg_first_contact_minutes.to_i > 240 ? "amber" : "blue",
        path: admin_leads_path(start_date: dashboard_window_start.to_date.iso8601, end_date: @dashboard_end_date.iso8601)
      }
    ]

    {
      question: "O atendimento está dentro do SLA?",
      answer: @sla_overdue_leads.to_i.positive? ? "#{@sla_overdue_leads} lead(s) vencidos no primeiro contato." : "Sem vencimento crítico de primeiro contato.",
      tone: @sla_overdue_leads.to_i.positive? ? "red" : "blue",
      icon: "stopwatch",
      path: admin_leads_path(attention_filter: "sla_overdue"),
      rows: rows,
      empty: "Sem dados de SLA no período."
    }
  end

  def whatsapp_attention_investigation
    rows = pending_whatsapp_reply_scope
      .includes(:lead, :assigned_admin_user)
      .order(Arel.sql("whatsapp_conversations.last_message_at DESC NULLS LAST, whatsapp_conversations.updated_at DESC"))
      .limit(5)
      .map do |conversation|
        owner = conversation.assigned_admin_user || conversation.lead&.admin_user
        {
          label: conversation.display_name.presence || "Conversa #{conversation.id}",
          value: conversation.unread_count.to_i,
          detail: owner ? "aguardando resposta de #{owner.name}" : "sem responsável claro no atendimento",
          tone: owner ? "amber" : "red",
          path: admin_whatsapp_conversation_path(conversation)
        }
      end
    rows << {
      label: "Tempo médio de resposta",
      value: @avg_whatsapp_response_minutes,
      detail: @avg_whatsapp_response_minutes.to_i.positive? ? "minutos nas conversas respondidas no período" : "sem respostas registradas no período",
      tone: @avg_whatsapp_response_minutes.to_i > 60 ? "amber" : "blue",
      path: admin_whatsapp_conversations_path
    }

    {
      question: "WhatsApp está ficando sem retorno?",
      answer: rows.any? ? "#{@pending_whatsapp_conversations} conversa(s) abertas aguardam resposta da equipe." : "Nenhuma conversa aberta sem retorno agora.",
      tone: rows.any? ? "red" : "green",
      icon: "whatsapp",
      path: admin_whatsapp_conversations_path(filter: "pending_reply"),
      rows: rows,
      empty: "Sem conversa aberta aguardando resposta."
    }
  end

  def funnel_bottleneck_investigation
    rows = funnel_bottleneck_rows

    {
      question: "Onde o funil está travando?",
      answer: rows.any? ? "Etapas abertas com maior volume parado há mais de 48h." : "Nenhum gargalo de etapa aberto agora.",
      tone: rows.any? ? "amber" : "green",
      icon: "filter-circle",
      path: admin_root_path(dashboard_date_params(tab: "leads")),
      rows: rows,
      empty: "Sem etapa travada no período."
    }
  end

  def property_attention_investigation
    rows = property_attention_rows

    {
      question: "Quais imóveis têm demanda sem avanço?",
      answer: rows.any? ? "Imóveis com leads no período e nenhuma visita registrada." : "Nenhum imóvel com demanda travada no período.",
      tone: rows.any? ? "amber" : "green",
      icon: "buildings",
      path: admin_root_path(dashboard_date_params(tab: "properties")),
      rows: rows,
      empty: "Sem imóvel com lead sem visita no período."
    }
  end

  def catalog_bottleneck_investigation
    rows = catalog_quality_metrics
      .select { |metric| metric[:value].to_i.positive? }
      .sort_by { |metric| -metric[:value].to_i }
      .first(4)
      .map do |metric|
        {
          label: metric[:label],
          value: metric[:value],
          detail: metric[:detail].presence || "Corrigir publicação",
          tone: metric[:tone],
          path: admin_habitations_path(metric[:path_params].presence || { ownership: "all", dashboard_quality: metric[:filter] })
        }
      end

    {
      question: "Qual gargalo bloqueia publicação?",
      answer: rows.any? ? "Itens que impedem o imóvel de vender melhor no site." : "Catálogo sem gargalos críticos de publicação.",
      tone: rows.any? ? "amber" : "green",
      icon: "clipboard2-pulse",
      path: admin_habitations_path(ownership: "all"),
      rows: rows,
      empty: "Nenhum gargalo crítico encontrado."
    }
  end

  def demand_channel_investigation
    acquisition = lead_acquisition_result

    rows = acquisition[:channels].first(4).map do |channel|
      {
        label: channel[:label],
        value: channel[:count],
        detail: "#{channel[:percentage]}% dos leads",
        tone: channel[:key] == "direct" ? "amber" : "blue",
        path: admin_leads_path(
          channel.fetch(:filter_params, { attribution_channel: channel[:key] }).merge(
            start_date: dashboard_window_start.to_date.iso8601,
            end_date: @dashboard_end_date.iso8601,
            broker_id: @dashboard_broker_id
          )
        )
      }
    end

    {
      question: "De onde vem a demanda útil?",
      answer: acquisition[:attribution_rate].to_f.positive? ? "#{acquisition[:attribution_rate]}% dos leads têm origem identificada." : "Origem ainda pouco rastreada neste período.",
      tone: acquisition[:unknown].to_i.positive? ? "amber" : "blue",
      icon: "signpost-split",
      path: admin_root_path(dashboard_date_params(tab: "leads")),
      rows: rows,
      empty: "Sem leads no período para comparar canais."
    }
  end

  def service_sla_rows
    [
      {
        label: "Tarefas vencidas",
        value: @lead_overdue_tasks,
        detail: "Tarefas pendentes passaram do prazo dentro dos leads",
        tone: @lead_overdue_tasks.to_i.positive? ? "red" : "green",
        path: admin_leads_path(attention_filter: "task_overdue")
      },
      {
        label: "Tarefas de hoje",
        value: @lead_tasks_due_today,
        detail: "Tarefas que vencem hoje dentro dos leads",
        tone: @lead_tasks_due_today.to_i.positive? ? "amber" : "green",
        path: admin_leads_path(attention_filter: "task_due_today")
      },
      {
        label: "Sem primeiro contato",
        value: @no_first_contact_leads,
        detail: "Leads sem registro de atendimento no histórico",
        tone: @no_first_contact_leads.to_i.positive? ? "red" : "green",
        path: admin_leads_path(attention_filter: "no_first_contact", start_date: dashboard_window_start.to_date.iso8601, end_date: @dashboard_end_date.iso8601)
      },
      {
        label: "SLA #{first_contact_sla_hours}h vencido",
        value: @sla_overdue_leads,
        detail: "Entraram há mais de #{first_contact_sla_hours}h e ainda não receberam atendimento",
        tone: @sla_overdue_leads.to_i.positive? ? "red" : "green",
        path: admin_leads_path(attention_filter: "sla_overdue", start_date: dashboard_window_start.to_date.iso8601, end_date: @dashboard_end_date.iso8601)
      },
      {
        label: "Sem responsável",
        value: @unassigned_open_leads,
        detail: "Leads abertos sem corretor responsável",
        tone: @unassigned_open_leads.to_i.positive? ? "red" : "green",
        path: admin_leads_path(broker_id: "unassigned", attention_filter: "unassigned")
      }
    ]
  end

  def load_service_sla_metrics
    active_lead_statuses_with_blank = active_lead_status_values_with_blank
    @lead_overdue_tasks = dashboard_task_scope.atrasadas.count
    @lead_tasks_due_today = dashboard_task_scope.hoje.count
    @unassigned_open_leads = @lead_scope.where(admin_user_id: nil, status: active_lead_statuses_with_blank).count
    @no_first_contact_leads = no_first_contact_scope.count
    @sla_overdue_leads = no_first_contact_scope.where("leads.created_at < ?", first_contact_sla_hours.hours.ago).count
  end

  def broker_attention_rows
    counts = @lead_scope
      .where(status: active_lead_status_values_with_blank)
      .then { |scope| attention_leads(scope) }
      .group(:admin_user_id)
      .count
    return [] if counts.empty?

    names = current_tenant.admin_users.where(id: counts.keys.compact).pluck(:id, :name).to_h

    counts.map do |admin_user_id, count|
      {
        label: admin_user_id ? names[admin_user_id].presence || "Corretor" : "Sem responsável",
        value: count,
        detail: admin_user_id ? "ações pendentes em leads" : "atribuir responsável",
        tone: admin_user_id ? "amber" : "red",
        path: admin_user_id ? admin_leads_path(broker_id: admin_user_id, attention_filter: "requires_action") : admin_leads_path(broker_id: "unassigned", attention_filter: "requires_action")
      }
    end.sort_by { |row| [-row[:value].to_i, row[:label].to_s] }.first(5)
  end

  def funnel_bottleneck_rows
    active_statuses = active_lead_status_values_with_blank
    open_scope = @lead_scope.where(status: active_statuses)
    totals = open_scope.group(:status).count
    stalled = open_scope.where("leads.updated_at < ?", 2.days.ago).group(:status).count

    totals.map do |status, total|
      canonical_status = Lead.status_value(status.presence || Lead.default_status)
      stalled_count = stalled[status].to_i
      next if stalled_count.zero?

      {
        label: canonical_status,
        value: stalled_count,
        detail: "#{percentage(stalled_count, total)}% parados de #{total} lead(s) abertos",
        tone: stalled_count.positive? ? "amber" : "green",
        path: admin_leads_path(status: canonical_status, attention_filter: "stalled")
      }
    end.compact.sort_by { |row| [-row[:value].to_i, row[:label].to_s] }.first(5)
  end

  def property_attention_rows
    period_scope = active_dashboard_leads_scope.where("leads.created_at >= ?", dashboard_window_start).where.not(property_id: nil)
    lead_counts = period_scope.group(:property_id).count
    return [] if lead_counts.empty?

    property_ids_with_visits = Appointment
      .joins(:lead)
      .merge(period_scope)
      .where(kind: "visita")
      .where.not(leads: { property_id: nil })
      .distinct
      .pluck("leads.property_id")
    candidate_ids = lead_counts.keys - property_ids_with_visits
    return [] if candidate_ids.empty?

    properties = scoped_dashboard_catalog_habitations
      .where(id: candidate_ids)
      .pluck(:id, :codigo, :titulo_anuncio, :nome_empreendimento)
      .index_by(&:first)

    candidate_ids.map do |property_id|
      property = properties[property_id]
      next unless property

      _id, codigo, title, development = property
      label = [codigo, title.presence || development].compact_blank.join(" · ")
      {
        label: label.presence || "Imóvel #{property_id}",
        value: lead_counts[property_id],
        detail: "lead(s) no período e nenhuma visita registrada",
        tone: "amber",
        path: admin_leads_path(
          property_q: codigo,
          start_date: dashboard_window_start.to_date.iso8601,
          end_date: @dashboard_end_date.iso8601
        )
      }
    end.compact.sort_by { |row| [-row[:value].to_i, row[:label].to_s] }.first(5)
  end

  def property_low_progress_rows
    @property_low_progress_rows ||= begin
      period_scope = active_dashboard_leads_scope.where("leads.created_at >= ?", dashboard_window_start).where.not(property_id: nil)
      lead_counts = period_scope.group(:property_id).count

      if lead_counts.empty?
        []
      else
        progressed_property_ids = (
          Appointment.joins(:lead)
            .merge(period_scope)
            .where(kind: "visita")
            .where.not(leads: { property_id: nil })
            .distinct
            .pluck("leads.property_id") |
          Proposal.joins(:lead)
            .merge(period_scope)
            .where.not(status: "rascunho")
            .where.not(leads: { property_id: nil })
            .distinct
            .pluck("leads.property_id")
        )
        candidate_ids = lead_counts.select { |_property_id, count| count.to_i >= 2 }.keys - progressed_property_ids

        if candidate_ids.empty?
          []
        else
          public_signal_counts = scoped_public_navigation_events
            .where("public_navigation_events.occurred_at >= ?", dashboard_window_start)
            .where(name: %w[property_view property_whatsapp_click property_phone_click lead_form_submitted])
            .where(habitation_id: candidate_ids)
            .group(:habitation_id)
            .count
          properties = scoped_dashboard_catalog_habitations
            .where(id: candidate_ids)
            .pluck(:id, :codigo, :titulo_anuncio, :nome_empreendimento)
            .index_by(&:first)

          candidate_ids.map do |property_id|
            property = properties[property_id]
            next unless property

            _id, codigo, title, development = property
            lead_count = lead_counts[property_id].to_i
            public_signals = public_signal_counts[property_id].to_i
            label = [codigo, title.presence || development].compact_blank.join(" · ")
            {
              label: label.presence || "Imóvel #{property_id}",
              value: lead_count + public_signals,
              detail: "#{lead_count} lead(s), #{public_signals} sinal(is) públicos e nenhuma visita/proposta",
              tone: "amber",
              path: admin_leads_path(
                property_q: codigo,
                start_date: dashboard_window_start.to_date.iso8601,
                end_date: @dashboard_end_date.iso8601
              )
            }
          end.compact.sort_by { |row| [-row[:value].to_i, row[:label].to_s] }.first(6)
        end
      end
    end
  end

  def lead_response_question
    total_attention = @attention_open_leads.to_i
    if total_attention.positive?
      details = []
      details << "#{@holding_leads} represado(s)" if @holding_leads.to_i.positive?
      details << "#{@unassigned_open_leads} sem responsável" if @unassigned_open_leads.to_i.positive?
      details << "#{@lead_overdue_tasks} tarefa(s) vencida(s)" if @lead_overdue_tasks.to_i.positive?
      details << "#{@sla_overdue_leads} SLA vencido" if @sla_overdue_leads.to_i.positive?
      {
        question: "Quem precisa agir agora?",
        answer: details.to_sentence,
        metric: total_attention,
        tone: "red",
        icon: "person-exclamation",
        action: "Abrir leads",
        path: admin_leads_path(attention_filter: "requires_action"),
        priority: 10,
        attention: true,
        featured: true
      }
    else
      {
        question: "Quem precisa agir agora?",
        answer: "Nenhum lead aberto exige atenção imediata.",
        metric: 0,
        tone: "green",
        icon: "check2-circle",
        action: "Ver leads",
        path: admin_leads_path(attention_filter: "requires_action"),
        priority: 70,
        attention: false
      }
    end
  end

  def demand_generation_question
    change = @leads_period_change
    if change.nil?
      answer = "#{@current_period_leads} lead(s) no período atual. Ainda sem base anterior para comparação."
      tone = @current_period_leads.to_i.positive? ? "blue" : "amber"
      attention = @current_period_leads.to_i.zero?
    elsif change.negative?
      answer = "#{@current_period_leads} lead(s), #{change.abs}% abaixo do período anterior."
      tone = "amber"
      attention = true
    else
      answer = "#{@current_period_leads} lead(s), #{change}% acima do período anterior."
      tone = "green"
      attention = false
    end

    {
      question: "A operação está gerando demanda?",
      answer: answer,
      metric: @current_period_leads,
      tone: tone,
      icon: "graph-up-arrow",
      action: "Analisar origem",
      path: admin_root_path(dashboard_date_params(tab: "leads")),
      priority: attention ? 30 : 80,
      attention: attention
    }
  end

  def catalog_readiness_question
    quality_metrics = catalog_quality_metrics
    issue_count = quality_metrics.sum { |metric| metric[:value].to_i }
    worst_metric = quality_metrics.max_by { |metric| metric[:value].to_i }

    if issue_count.positive?
      worst_count = worst_metric[:value].to_i
      total_detail = issue_count == worst_count ? "" : " #{issue_count} ponto(s) no total."
      {
        question: "A carteira está pronta para vender?",
        answer: "#{worst_count} imóvel(is) no principal gargalo: #{worst_metric[:label].downcase}.#{total_detail}",
        metric: worst_count,
        tone: worst_metric[:tone] == "red" ? "red" : "amber",
        icon: "clipboard2-pulse",
        action: "Corrigir catálogo",
        path: admin_habitations_path(worst_metric[:path_params].presence || { ownership: "all", dashboard_quality: worst_metric[:filter] }),
        priority: 20,
        attention: true
      }
    else
      {
        question: "A carteira está pronta para vender?",
        answer: "Nenhum gargalo crítico de publicação encontrado.",
        metric: 0,
        tone: "green",
        icon: "clipboard2-check",
        action: "Ver imóveis",
        path: admin_habitations_path(ownership: "all"),
        priority: 90,
        attention: false
      }
    end
  end

  def intake_flow_question
    if @drafts_count.to_i.positive?
      detail = @stale_drafts_count.to_i.positive? ? "#{@stale_drafts_count} antigo(s) há mais de 30 dias" : "#{@drafts_count} rascunho(s) aguardando avanço"
      {
        question: "A captação está travada?",
        answer: detail,
        metric: @drafts_count,
        tone: @stale_drafts_count.to_i.positive? ? "amber" : "blue",
        icon: "journal-check",
        action: "Revisar captações",
        path: admin_captacoes_path(status: "draft"),
        priority: 40,
        attention: true
      }
    else
      {
        question: "A captação está travada?",
        answer: "Não há captações em rascunho no escopo atual.",
        metric: 0,
        tone: "green",
        icon: "journal-check",
        action: "Ver captações",
        path: admin_captacoes_path,
        priority: 95,
        attention: false
      }
    end
  end

  def distribution_question
    return unless @is_admin_view

    if @distribution_rules_total.to_i.zero?
      {
        question: "Os leads estão sendo distribuídos?",
        answer: "Nenhuma regra de distribuição configurada.",
        metric: 0,
        tone: "amber",
        icon: "diagram-3",
        action: "Configurar regras",
        path: admin_distribution_rules_path,
        priority: 50,
        attention: true
      }
    elsif @distribution_rules_active.to_i.zero?
      {
        question: "Os leads estão sendo distribuídos?",
        answer: "#{@distribution_rules_total} regra(s) cadastrada(s), mas nenhuma ativa.",
        metric: @distribution_rules_total,
        tone: "red",
        icon: "diagram-3",
        action: "Ativar regras",
        path: admin_distribution_rules_path,
        priority: 50,
        attention: true
      }
    else
      {
        question: "Os leads estão sendo distribuídos?",
        answer: "#{@distribution_rules_active} de #{@distribution_rules_total} regra(s) ativas para #{@brokers_active} corretor(es).",
        metric: @distribution_rules_active,
        tone: "green",
        icon: "diagram-3",
        action: "Ver regras",
        path: admin_distribution_rules_path,
        priority: 85,
        attention: false
      }
    end
  end

  def percentage(value, total)
    return 0.0 if total.to_i.zero?

    ((value.to_f / total) * 100).round(1)
  end

  def percentage_change(current, previous)
    return nil if previous.to_i.zero?

    (((current.to_f - previous) / previous) * 100).round(1)
  end

  def active_lead_status_values
    @active_lead_status_values ||= begin
      pipeline_statuses = current_tenant.lead_pipeline_stages.active.where(stage_type: "open").pluck(:name)
      fallback_statuses = Lead::LEGACY_STATUSES - Lead.non_operational_status_values(tenant: current_tenant)
      (pipeline_statuses.presence || fallback_statuses).uniq
    end
  end

  def active_lead_status_values_with_blank
    active_lead_status_values + [nil]
  end

  def lost_lead_status_values
    @lost_lead_status_values ||= begin
      pipeline_statuses = current_tenant.lead_pipeline_stages.active.where(stage_type: "lost").pluck(:name)
      (pipeline_statuses.presence || [Lead.status_value(:descartado)]).map { |status| Lead.status_value(status, tenant: current_tenant) }.uniq
    end
  end

  def invalid_operational_lead_status_values
    @invalid_operational_lead_status_values ||= Lead.non_operational_status_values(tenant: current_tenant)
  end

  def terminal_lead_status_values
    @terminal_lead_status_values ||= begin
      pipeline_statuses = current_tenant.lead_pipeline_stages.active.where(stage_type: %w[won lost archived]).pluck(:name)
      (pipeline_statuses.presence || [Lead.status_value(:descartado), Lead.status_value(:concluido)]).map { |status| Lead.status_value(status, tenant: current_tenant) }.uniq
    end
  end

  def lead_status_change_logs
    @lead_status_change_logs ||= current_tenant.lead_audit_logs
      .where(lead_id: @lead_scope.select(:id), action: "status_changed")
      .where("lead_audit_logs.created_at >= ?", dashboard_window_start)
      .where("'status' = ANY(lead_audit_logs.changed_fields)")
      .pluck(:changeset)
  end

  def temperature_row(label, tag, stale_before, tone)
    ids = interest_classification_ids(tag, stale_before)
    {
      label: label,
      value: ids.size,
      detail: "interpretação #{tag} sem atualização desde #{I18n.l(stale_before.to_date)}",
      tone: ids.any? ? tone : "green",
      path: admin_leads_path(attention_filter: "interest_#{tag}_stalled")
    }
  end

  def interest_classification_ids(classification, stale_before)
    @interest_classification_ids ||= {}
    @interest_classification_ids[[classification, stale_before.to_i]] ||= begin
      scope = @lead_scope
        .where(status: active_lead_status_values_with_blank)
        .where("leads.updated_at < ?", stale_before)
      hot_ids = hot_interest_lead_ids(scope)

      case classification
      when "quente" then hot_ids
      when "morno" then warm_interest_lead_ids(scope) - hot_ids
      else []
      end
    end
  end

  def hot_interest_lead_ids(scope)
    lead_ids = scope.select(:id)
    direct_share_ids, collection_share_ids = share_event_lead_ids(scope, %w[interest_created interest_repeated], 7.days.ago)

    [
      Proposal.where(lead_id: lead_ids, status: %w[enviada visualizada aceita])
        .where("validade IS NULL OR validade >= ?", Date.current)
        .distinct.pluck(:lead_id),
      current_tenant.appointments.where(lead_id: lead_ids, kind: "visita", status: "agendado")
        .where("starts_at >= ?", Time.current)
        .distinct.pluck(:lead_id),
      current_tenant.appointments.where(lead_id: lead_ids, kind: "visita", status: "realizado")
        .where("starts_at >= ?", 14.days.ago)
        .distinct.pluck(:lead_id),
      direct_share_ids,
      collection_share_ids
    ].flatten.compact.uniq
  end

  def warm_interest_lead_ids(scope)
    lead_ids = scope.select(:id)
    direct_share_ids, collection_share_ids = share_event_lead_ids(scope, %w[property_opened collection_opened], 14.days.ago)

    [
      LeadActivity.where(lead_id: lead_ids).contact_attempts
        .where("lead_activities.metadata ->> 'contact_result' = ?", "falou_com_cliente")
        .where("lead_activities.created_at >= ?", 14.days.ago)
        .distinct.pluck(:lead_id),
      current_tenant.public_navigation_events.where(lead_id: lead_ids, name: %w[property_view property_search property_favorite_added])
        .where("occurred_at >= ?", 14.days.ago)
        .distinct.pluck(:lead_id),
      direct_share_ids,
      collection_share_ids
    ].flatten.compact.uniq
  end

  def share_event_lead_ids(scope, event_types, since)
    lead_ids = scope.select(:id)
    matching_collections = current_tenant.ai_property_share_collections.where(lead_id: lead_ids)
    events = current_tenant.ai_property_share_audit_events.where(event_type: event_types).where("ai_property_share_audit_events.created_at >= ?", since)

    [
      events.where(lead_id: lead_ids).distinct.pluck(:lead_id),
      matching_collections.joins(:audit_events)
        .merge(events)
        .distinct.pluck(:lead_id)
    ]
  end

  def formatted_currency(value)
    number = value.to_f
    formatted = format("%.2f", number).tr(".", ",")
    "R$ #{formatted.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1.')}"
  rescue TypeError
    "R$ 0,00"
  end

  def attention_leads(scope)
    Leads::AttentionQuery.new(
      scope: scope, sla_hours: first_contact_sla_hours, contact_kinds: CONTACT_ACTIVITY_KINDS
    ).call
  end

  def no_first_contact_scope
    @no_first_contact_scope ||= @lead_scope
      .where("leads.created_at >= ?", dashboard_window_start)
      .where(status: active_lead_status_values_with_blank)
      .where.not(id: human_contact_activity_scope.select(:lead_id))
  end

  def pending_whatsapp_reply_scope
    @pending_whatsapp_reply_scope ||= dashboard_whatsapp_conversation_scope.pending_reply_since(dashboard_window_start)
  end

  def lead_acquisition_result
    @lead_acquisition_result ||= Rails.cache.fetch(
      ["dashboard-lead-acquisition-v4", current_tenant.id, current_admin_user.id, @dashboard_start_date, @dashboard_end_date, @dashboard_broker_ids, @dashboard_business_type],
      expires_in: DASHBOARD_AGGREGATE_CACHE_EXPIRATION
    ) do
      Dashboard::LeadAcquisitionQuery.new(
        scope: valid_dashboard_leads_scope,
        starts_at: dashboard_window_start,
        ends_at: dashboard_window_end,
        tenant: current_tenant
      ).call
    end
  end

  def average_whatsapp_response_minutes
    value = WhatsappMessage
      .where(tenant_id: current_tenant.id, direction: "inbound")
      .where(whatsapp_conversation_id: dashboard_whatsapp_conversation_scope.select(:id))
      .where("whatsapp_messages.created_at >= ?", dashboard_window_start)
      .joins(
        <<~SQL.squish
          INNER JOIN LATERAL (
            SELECT MIN(outbound_messages.created_at) AS first_reply_at
            FROM whatsapp_messages outbound_messages
            WHERE outbound_messages.whatsapp_conversation_id = whatsapp_messages.whatsapp_conversation_id
              AND outbound_messages.tenant_id = whatsapp_messages.tenant_id
              AND outbound_messages.direction = 'outbound'
              AND outbound_messages.created_at > whatsapp_messages.created_at
          ) first_reply ON first_reply.first_reply_at IS NOT NULL
        SQL
      )
      .average(Arel.sql("EXTRACT(EPOCH FROM (first_reply.first_reply_at - whatsapp_messages.created_at)) / 60.0"))

    value.to_f.round
  end

  def dashboard_whatsapp_conversation_scope
    scope = current_tenant.whatsapp_conversations
    owner_ids = visible_owner_ids(:whatsapp_inbox)
    return scope if owner_ids.nil?

    scope.left_joins(:lead).where(
      "whatsapp_conversations.assigned_admin_user_id IN (:ids) OR leads.admin_user_id IN (:ids)",
      ids: owner_ids
    )
  end

  def average_first_contact_minutes
    contacted = LeadActivity
      .joins(:lead)
      .merge(valid_dashboard_leads_scope.where("leads.created_at >= ?", dashboard_window_start))
      .human_operational
      .where(kind: CONTACT_ACTIVITY_KINDS)
      .group("leads.id", "leads.created_at")
      .minimum("lead_activities.created_at")

    durations = contacted.filter_map do |(_lead_id, lead_created_at), first_contact_at|
      next if lead_created_at.blank? || first_contact_at.blank?

      ((first_contact_at - lead_created_at) / 60.0).round
    end

    return 0 if durations.empty?

    (durations.sum.to_f / durations.size).round
  end

  def human_contact_activity_scope
    LeadActivity.human_operational.where(kind: CONTACT_ACTIVITY_KINDS)
  end

  def broker_performance_rows
    period_scope = valid_dashboard_leads_scope(scoped_dashboard_report_leads(:dashboard_broker_performance))
      .where(leads: { created_at: dashboard_window_start..dashboard_window_end })
      .where.not(admin_user_id: nil)
      .includes(:distribution_rule)
    leads = period_scope.order("leads.created_at DESC").to_a
    lead_ids = leads.map(&:id)
    responded_ids = LeadActivity.human_operational
      .where(lead_id: lead_ids)
      .where("lead_activities.metadata ->> 'contact_result' = ?", "falou_com_cliente")
      .distinct
      .pluck(:lead_id)
    responded_ids |= LeadActivity
      .where(lead_id: lead_ids, kind: "whatsapp_in")
      .distinct
      .pluck(:lead_id)
    pool_ids = LeadActivity
      .where(lead_id: lead_ids, kind: %w[pocket_pool_ready accepted])
      .where("lead_activities.kind = ? OR lead_activities.metadata ->> 'shark_tank' = ?", "pocket_pool_ready", "true")
      .distinct
      .pluck(:lead_id)
    performance_events = LeadActivity
      .where(lead_id: lead_ids, kind: %w[distributed pocket_pool_ready shark_tank_ready accepted secure_link_accessed])
      .order(:created_at)
      .to_a
    entry_started_at_by_lead = broker_performance_entry_starts(leads, pool_ids, performance_events)
    attended_at_by_lead = broker_performance_attended_at(leads, performance_events, entry_started_at_by_lead)
    expired_ids = LeadActivity.where(lead_id: lead_ids, kind: "pocket_expired").distinct.pluck(:lead_id)
    contact_attempts_by_lead = broker_performance_contact_attempt_scope
      .where(lead_id: lead_ids)
      .order(created_at: :desc)
      .group_by(&:lead_id)

    leads_by_broker = leads.group_by(&:admin_user_id)
    broker_ids = leads_by_broker.keys.compact
    names = current_tenant.admin_users.where(id: broker_ids).pluck(:id, :name).to_h

    broker_ids.map do |broker_id|
      row_leads = leads_by_broker[broker_id] || []
      pool_leads, rotary_leads = row_leads.partition { |lead| pool_ids.include?(lead.id) }
      no_first_contact_count = row_leads.count { |lead| !lead_attended?(lead, attended_at_by_lead) }
      opened_count = row_leads.size - no_first_contact_count
      contact_attempts_count = row_leads.sum { |lead| contact_attempts_by_lead[lead.id].to_a.size }
      {
        id: broker_id,
        name: names[broker_id] || "Corretor",
        total: row_leads.size,
        rotary_count: rotary_leads.size,
        rotary_avg_label: average_first_contact_label(rotary_leads, attended_at_by_lead, entry_started_at_by_lead),
        pool_count: pool_leads.size,
        pool_avg_label: average_first_contact_label(pool_leads, attended_at_by_lead, entry_started_at_by_lead),
        opened_count: opened_count,
        not_opened_count: row_leads.size - opened_count,
        contact_attempts_count: contact_attempts_count,
        no_first_contact_count: no_first_contact_count,
        expired_count: row_leads.count { |lead| expired_ids.include?(lead.id) },
        leads: broker_performance_lead_rows(row_leads, pool_ids, responded_ids, attended_at_by_lead, entry_started_at_by_lead, expired_ids, contact_attempts_by_lead)
      }
    end.sort_by { |row| [-row[:not_opened_count], -row[:expired_count], -row[:total]] }.first(6)
  end

  def broker_performance_report_xlsx
    rows = [
      dashboard_report_xlsx_row(:title, ["Performance dos Corretores"]),
      dashboard_report_xlsx_row(:period, ["Período", @dashboard_period_label]),
      dashboard_report_xlsx_blank_row
    ]

    broker_performance_rows.each do |row|
      rows << dashboard_report_xlsx_row(:group_header, ["Corretor", "Total", "Rodízio", "Bolsão", "Atendidos", "Tentou contato"])
      rows << dashboard_report_xlsx_row(
        :group_summary,
        [
          row[:name],
          "#{row[:total]} leads",
          dashboard_report_xlsx_badge(row[:rotary_count], :rotary),
          dashboard_report_xlsx_badge(row[:pool_count], :pool),
          dashboard_report_xlsx_badge(row[:opened_count], :positive),
          dashboard_report_xlsx_badge(row[:contact_attempts_count], :contact)
        ]
      )
      rows << dashboard_report_xlsx_row(:lead_header, ["Lead", "Recebeu", "Abriu", "Tentou contato", "Situação", "Recebido"])
      row[:leads].each do |lead|
        rows << dashboard_report_xlsx_row(
          :lead_body,
          [
            lead[:name],
            dashboard_report_xlsx_badge(lead[:entry_label], lead[:entry_label].to_s.match?(/bols/i) ? :pool : :rotary),
            dashboard_report_xlsx_badge(lead[:opened_label], lead[:opened_label].to_s.match?(/não abriu/i) ? :danger : :positive),
            dashboard_report_xlsx_badge(lead[:contact_label], lead[:contact_label].to_s.match?(/nenhuma/i) ? :muted : :contact),
            dashboard_report_xlsx_badge(lead[:story_label], dashboard_report_story_style(lead[:story_label])),
            I18n.l(lead[:created_at], format: :short)
          ]
        )
      end
      rows << dashboard_report_xlsx_blank_row
    end

    dashboard_report_xlsx_package(rows, "Corretores")
  end

  def campaign_performance_result
    @campaign_performance_result ||= Dashboard::CampaignPerformanceQuery.new(
      scope: valid_dashboard_leads_scope(scoped_dashboard_report_leads(:dashboard_campaign_performance)),
      tenant: current_tenant,
      starts_at: dashboard_window_start,
      ends_at: dashboard_window_end,
      period_label: @dashboard_period_label
    ).call
  end

  def campaign_performance_report_xlsx
    rows = [
      dashboard_report_xlsx_row(:title, ["Performance de Campanhas e Canais"]),
      dashboard_report_xlsx_row(:period, ["Período", @dashboard_period_label]),
      dashboard_report_xlsx_blank_row
    ]

    campaign_performance_result.rows.each do |row|
      rows << dashboard_report_xlsx_row(:group_header, ["Campanha/canal", "Detalhe", "Leads", "Atendidos", "Tentou contato", "Oportunidades", "Fechados", "Taxa de fechamento"])
      rows << dashboard_report_xlsx_row(
        :group_summary,
        [
          row[:title],
          row[:detail],
          dashboard_report_xlsx_badge(row[:total], :lead),
          dashboard_report_xlsx_badge(row[:attended_count], :positive),
          dashboard_report_xlsx_badge(row[:contacted_count], row[:contacted_count].to_i.positive? ? :contact : :muted),
          dashboard_report_xlsx_badge(row[:opportunity_count], row[:opportunity_count].to_i.positive? ? :opportunity : :muted),
          dashboard_report_xlsx_badge(row[:closed_count], row[:closed_count].to_i.positive? ? :positive : :muted),
          "#{row[:conversion_rate]}%"
        ]
      )
      rows << dashboard_report_xlsx_row(:lead_header, ["Lead", "Origem", "Corretor", "Atendimento", "Tentou contato", "Resultado", "Imóvel", "Recebido"])
      row[:leads].each do |lead|
        rows << dashboard_report_xlsx_row(
          :lead_body,
          [
            lead[:name],
            lead[:source_label],
            lead[:broker_name],
            dashboard_report_xlsx_badge(lead[:opened_label], lead[:opened_label].to_s.match?(/não abriu/i) ? :danger : :positive),
            dashboard_report_xlsx_badge(lead[:contact_label], lead[:contact_label].to_s.match?(/nenhuma|0 /i) ? :muted : :contact),
            dashboard_report_xlsx_badge(lead[:result_label], dashboard_report_story_style(lead[:result_label])),
            lead[:property_label],
            I18n.l(lead[:created_at], format: :short)
          ]
        )
      end
      rows << dashboard_report_xlsx_blank_row
    end

    dashboard_report_xlsx_package(rows, "Campanhas")
  end

  def dashboard_report_story_style(label)
    text = label.to_s
    return :positive if text.match?(/cliente respondeu|negócio|fechado/i)
    return :opportunity if text.match?(/oportunidade|visita|proposta/i)
    return :warning if text.match?(/falta registrar|aguardando/i)
    return :danger if text.match?(/não abriu|sem abertura/i)

    :muted
  end

  def dashboard_report_xlsx_badge(value, style)
    { value: value, style: style }
  end

  def dashboard_report_xlsx_row(style, cells)
    normalized_cells = cells + Array.new(DASHBOARD_REPORT_XLSX_COLUMN_WIDTHS.size - cells.size)
    { style: style, cells: normalized_cells }
  end

  def dashboard_report_xlsx_blank_row
    dashboard_report_xlsx_row(:blank, [])
  end

  def dashboard_report_xlsx_package(rows, sheet_name)
    build_xlsx_package(
      "[Content_Types].xml" => dashboard_report_xlsx_content_types_xml,
      "_rels/.rels" => dashboard_report_xlsx_root_relationships_xml,
      "docProps/app.xml" => dashboard_report_xlsx_app_properties_xml,
      "docProps/core.xml" => dashboard_report_xlsx_core_properties_xml,
      "xl/workbook.xml" => dashboard_report_xlsx_workbook_xml(sheet_name),
      "xl/_rels/workbook.xml.rels" => dashboard_report_xlsx_workbook_relationships_xml,
      "xl/styles.xml" => dashboard_report_xlsx_styles_xml,
      "xl/worksheets/sheet1.xml" => dashboard_report_xlsx_sheet_xml(rows)
    )
  end

  def dashboard_report_xlsx_sheet_xml(rows)
    last_column = xlsx_column_name(DASHBOARD_REPORT_XLSX_COLUMN_WIDTHS.size)
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <dimension ref="A1:#{last_column}#{rows.size}"/>
        <sheetViews><sheetView workbookViewId="0"><pane ySplit="3" topLeftCell="A4" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
        <sheetFormatPr defaultRowHeight="19"/>
        <cols>
          #{DASHBOARD_REPORT_XLSX_COLUMN_WIDTHS.each_with_index.map { |width, index| %(<col min="#{index + 1}" max="#{index + 1}" width="#{width}" customWidth="1"/>) }.join}
        </cols>
        <sheetData>
          #{rows.each_with_index.map { |row, index| dashboard_report_xlsx_row_xml(index + 1, row) }.join}
        </sheetData>
        <autoFilter ref="A4:#{last_column}#{rows.size}"/>
        <pageMargins left="0.4" right="0.4" top="0.5" bottom="0.5" header="0.3" footer="0.3"/>
      </worksheet>
    XML
  end

  def dashboard_report_xlsx_row_xml(row_index, row)
    style_id = dashboard_report_xlsx_style_id(row[:style])
    cells = row.fetch(:cells).each_with_index.map do |value, column_index|
      cell_style = value.is_a?(Hash) ? dashboard_report_xlsx_style_id(value[:style]) : style_id
      cell_value = value.is_a?(Hash) ? value[:value] : value
      dashboard_report_xlsx_cell_xml(row_index, column_index + 1, cell_value, cell_style)
    end.join

    %(<row r="#{row_index}">#{cells}</row>)
  end

  def dashboard_report_xlsx_cell_xml(row_index, column_index, value, style_id)
    reference = "#{xlsx_column_name(column_index)}#{row_index}"
    return %(<c r="#{reference}" s="#{style_id}"/>) if value.blank?

    %(<c r="#{reference}" s="#{style_id}" t="inlineStr"><is><t>#{CGI.escapeHTML(value.to_s)}</t></is></c>)
  end

  def dashboard_report_xlsx_style_id(style)
    {
      blank: 0,
      title: 1,
      period: 2,
      group_header: 3,
      group_summary: 4,
      lead_header: 5,
      lead_body: 6,
      lead: 7,
      rotary: 8,
      pool: 9,
      positive: 10,
      contact: 11,
      opportunity: 12,
      warning: 13,
      danger: 14,
      muted: 15
    }.fetch(style || :blank)
  end

  def dashboard_report_xlsx_content_types_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
        <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
      </Types>
    XML
  end

  def dashboard_report_xlsx_root_relationships_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
      </Relationships>
    XML
  end

  def dashboard_report_xlsx_workbook_xml(sheet_name)
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="#{CGI.escapeHTML(sheet_name)}" sheetId="1" r:id="rId1"/></sheets>
      </workbook>
    XML
  end

  def dashboard_report_xlsx_workbook_relationships_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
      </Relationships>
    XML
  end

  def dashboard_report_xlsx_app_properties_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
        <Application>Unitymob</Application>
      </Properties>
    XML
  end

  def dashboard_report_xlsx_core_properties_xml
    generated_at = CGI.escapeHTML(Time.current.utc.iso8601)
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
        <dc:creator>Unitymob</dc:creator>
        <cp:lastModifiedBy>Unitymob</cp:lastModifiedBy>
        <dcterms:created xsi:type="dcterms:W3CDTF">#{generated_at}</dcterms:created>
        <dcterms:modified xsi:type="dcterms:W3CDTF">#{generated_at}</dcterms:modified>
      </cp:coreProperties>
    XML
  end

  def dashboard_report_xlsx_styles_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <fonts count="4">
          <font><sz val="11"/><name val="Arial"/><color rgb="FF1F2937"/></font>
          <font><b/><sz val="14"/><name val="Arial"/><color rgb="FFFFFFFF"/></font>
          <font><b/><sz val="11"/><name val="Arial"/><color rgb="FF1F2937"/></font>
          <font><b/><sz val="11"/><name val="Arial"/><color rgb="FFFFFFFF"/></font>
        </fonts>
        <fills count="12">
          <fill><patternFill patternType="none"/></fill>
          <fill><patternFill patternType="gray125"/></fill>
          <fill><patternFill patternType="solid"><fgColor rgb="FF1F2937"/><bgColor indexed="64"/></patternFill></fill>
          <fill><patternFill patternType="solid"><fgColor rgb="FFEAF2FF"/><bgColor indexed="64"/></patternFill></fill>
          <fill><patternFill patternType="solid"><fgColor rgb="FFDDEBFA"/><bgColor indexed="64"/></patternFill></fill>
          <fill><patternFill patternType="solid"><fgColor rgb="FFF3F7FC"/><bgColor indexed="64"/></patternFill></fill>
          <fill><patternFill patternType="solid"><fgColor rgb="FFF8FAFD"/><bgColor indexed="64"/></patternFill></fill>
          <fill><patternFill patternType="solid"><fgColor rgb="FFEAF3FF"/><bgColor indexed="64"/></patternFill></fill>
          <fill><patternFill patternType="solid"><fgColor rgb="FFF3E8FF"/><bgColor indexed="64"/></patternFill></fill>
          <fill><patternFill patternType="solid"><fgColor rgb="FFEAFBF1"/><bgColor indexed="64"/></patternFill></fill>
          <fill><patternFill patternType="solid"><fgColor rgb="FFFFF4DE"/><bgColor indexed="64"/></patternFill></fill>
          <fill><patternFill patternType="solid"><fgColor rgb="FFFFE8E8"/><bgColor indexed="64"/></patternFill></fill>
        </fills>
        <borders count="3">
          <border><left/><right/><top/><bottom/><diagonal/></border>
          <border><left style="thin"><color rgb="FFD6DEE8"/></left><right style="thin"><color rgb="FFD6DEE8"/></right><top style="thin"><color rgb="FFD6DEE8"/></top><bottom style="thin"><color rgb="FFD6DEE8"/></bottom><diagonal/></border>
          <border><left style="thin"><color rgb="FFFFFFFF"/></left><right style="thin"><color rgb="FFFFFFFF"/></right><top style="thin"><color rgb="FFFFFFFF"/></top><bottom style="thin"><color rgb="FFFFFFFF"/></bottom><diagonal/></border>
        </borders>
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="16">
          <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
          <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
          <xf numFmtId="0" fontId="2" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
          <xf numFmtId="0" fontId="2" fillId="4" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
          <xf numFmtId="0" fontId="2" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
          <xf numFmtId="0" fontId="2" fillId="5" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
          <xf numFmtId="0" fontId="0" fillId="6" borderId="1" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
          <xf numFmtId="0" fontId="2" fillId="7" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
          <xf numFmtId="0" fontId="2" fillId="7" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
          <xf numFmtId="0" fontId="2" fillId="8" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
          <xf numFmtId="0" fontId="2" fillId="9" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
          <xf numFmtId="0" fontId="2" fillId="10" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
          <xf numFmtId="0" fontId="2" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
          <xf numFmtId="0" fontId="2" fillId="10" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
          <xf numFmtId="0" fontId="2" fillId="11" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
          <xf numFmtId="0" fontId="2" fillId="5" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center"/></xf>
        </cellXfs>
        <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
        <dxfs count="0"/>
        <tableStyles count="0" defaultTableStyle="TableStyleMedium2" defaultPivotStyle="PivotStyleLight16"/>
      </styleSheet>
    XML
  end

  def xlsx_column_name(index)
    name = +""
    while index.positive?
      index -= 1
      name.prepend((65 + (index % 26)).chr)
      index /= 26
    end
    name
  end

  def build_xlsx_package(entries)
    offset = 0
    central_directory = +"".b
    file_data = +"".b
    mod_time, mod_date = xlsx_zip_timestamp

    entries.each do |path, content|
      name = path.b
      body = content.to_s.b
      crc = Zlib.crc32(body)
      local_header = [0x04034b50, 20, 0, 0, mod_time, mod_date, crc, body.bytesize, body.bytesize, name.bytesize, 0].pack("VvvvvvVVVvv")
      central_header = [0x02014b50, 20, 20, 0, 0, mod_time, mod_date, crc, body.bytesize, body.bytesize, name.bytesize, 0, 0, 0, 0, 0, offset].pack("VvvvvvvVVVvvvvvVV")

      file_data << local_header << name << body
      central_directory << central_header << name
      offset = file_data.bytesize
    end

    end_record = [0x06054b50, 0, 0, entries.size, entries.size, central_directory.bytesize, file_data.bytesize, 0].pack("VvvvvVVv")
    file_data << central_directory << end_record
  end

  def xlsx_zip_timestamp
    now = Time.current
    [
      (now.hour << 11) | (now.min << 5) | (now.sec / 2),
      ((now.year - 1980) << 9) | (now.month << 5) | now.day
    ]
  end

  def broker_performance_lead_rows(leads, pool_ids, responded_ids, attended_at_by_lead, entry_started_at_by_lead, expired_ids, contact_attempts_by_lead)
    leads.map do |lead|
      pool = pool_ids.include?(lead.id)
      attended_at = attended_at_by_lead[lead.id]
      entry_started_at = entry_started_at_by_lead[lead.id] || lead.created_at
      attended = lead_attended?(lead, attended_at_by_lead)
      attempts = contact_attempts_by_lead[lead.id] || []
      responded = responded_ids.include?(lead.id)

      {
        lead: lead,
        name: lead.name.presence || "Lead ##{lead.id}",
        entry_label: pool ? "Bolsão" : "Rodízio",
        entry_tone: pool ? "pool" : "rotary",
        first_contact_label: broker_performance_attendance_label(lead, attended_at, entry_started_at),
        opened_label: broker_performance_opened_label(lead, attended_at, entry_started_at, attended),
        opened_tone: attended ? "green" : "red",
        contact_label: broker_performance_contact_label(attempts),
        contact_tone: attempts.any? ? "amber" : "gray",
        story_label: broker_performance_story_label(attended: attended, attempts: attempts, responded: responded, expired: expired_ids.include?(lead.id)),
        story_tone: broker_performance_story_tone(attended: attended, attempts: attempts, responded: responded, expired: expired_ids.include?(lead.id)),
        contact_attempts: broker_performance_contact_attempt_rows(attempts),
        status: lead.status.presence || Lead.default_status,
        origin: lead.origin.presence || "Origem não informada",
        created_at: lead.created_at
      }
    end
  end

  def lead_attended?(lead, attended_at_by_lead)
    attended_at_by_lead[lead.id].present? || Lead.status_value(lead.status) == Lead.status_value(:em_atendimento)
  end

  def broker_performance_attendance_label(lead, attended_at, entry_started_at)
    return first_contact_delay_label(entry_started_at, attended_at) if attended_at.present?
    return "em atendimento sem registro" if Lead.status_value(lead.status) == Lead.status_value(:em_atendimento)

    "não abriu"
  end

  def broker_performance_opened_label(lead, attended_at, entry_started_at, attended)
    return "não abriu" unless attended
    return "abriu em #{first_contact_delay_label(entry_started_at, attended_at)}" if attended_at.present?

    broker_performance_attendance_label(lead, attended_at, entry_started_at)
  end

  def broker_performance_contact_label(attempts)
    count = attempts.size
    return "nenhuma tentativa" if count.zero?

    "#{count} #{'tentativa'.pluralize(count)}"
  end

  def broker_performance_contact_attempt_scope
    # Mesma origem do bloco "Histórico de contatos" do lead, limitada a tentativas reais.
    LeadActivity.human_operational.contact_attempts
  end

  def broker_performance_story_label(attended:, attempts:, responded:, expired:)
    unless attended
      return "cliente respondeu, mas sem abertura registrada" if responded
      return "tentativa registrada, mas sem abertura" if attempts.any?
      return "voltou para redistribuição" if expired

      return "aguardando abertura do corretor"
    end

    return "cliente respondeu" if responded
    return "tentou contato, aguardando cliente" if attempts.any?

    "corretor abriu, falta registrar tentativa"
  end

  def broker_performance_story_tone(attended:, attempts:, responded:, expired:)
    return "amber" unless attended

    return "green" if responded
    return "blue" if attempts.any?

    "amber"
  end

  def broker_performance_contact_attempt_rows(attempts)
    attempts.first(4).map do |activity|
      {
        kind: LeadActivity::CONTACT_KIND_LABELS[activity.meta("contact_kind").to_s] || "Contato",
        result: LeadActivity::CONTACT_RESULT_LABELS[activity.meta("contact_result").to_s] || "Sem resultado",
        body: activity.meta("body").to_s.strip.presence || "Sem observação registrada.",
        created_at: activity.created_at
      }
    end
  end

  def broker_performance_entry_starts(leads, pool_ids, events)
    events_by_lead = events.group_by(&:lead_id)

    leads.each_with_object({}) do |lead, starts|
      lead_events = events_by_lead[lead.id] || []
      starts[lead.id] = if pool_ids.include?(lead.id)
        lead_events.select { |activity| activity.kind.in?(%w[pocket_pool_ready shark_tank_ready]) }.map(&:created_at).max ||
          broker_performance_distribution_at(lead, lead_events) ||
          lead.created_at
      else
        broker_performance_distribution_at(lead, lead_events) || lead.created_at
      end
    end
  end

  def broker_performance_distribution_at(lead, events)
    events
      .select { |activity| activity.kind == "distributed" && activity.meta("admin_user_id").to_i == lead.admin_user_id.to_i }
      .map(&:created_at)
      .max
  end

  def broker_performance_attended_at(leads, events, entry_starts)
    events_by_lead = events.group_by(&:lead_id)

    leads.each_with_object({}) do |lead, attended|
      entry_started_at = entry_starts[lead.id] || lead.created_at
      attended_at = (events_by_lead[lead.id] || [])
        .select { |activity| broker_performance_attendance_event?(activity) && activity.created_at >= entry_started_at }
        .map(&:created_at)
        .min
      attended[lead.id] = attended_at if attended_at.present?
    end
  end

  def broker_performance_attendance_event?(activity)
    return true if activity.kind == "accepted"

    activity.kind == "secure_link_accessed" &&
      (activity.meta("contact").to_s.in?(%w[attend whatsapp]) || activity.meta("action_type").to_s.in?(%w[attend phone]))
  end

  def first_contact_delay_label(entry_started_at, first_contact_at)
    duration_label(first_contact_at - entry_started_at)
  end

  def average_first_contact_label(leads, first_contacts, entry_starts)
    seconds = leads.filter_map do |lead|
      first_contact_at = first_contacts[lead.id]
      entry_started_at = entry_starts[lead.id] || lead.created_at
      next if first_contact_at.blank?

      first_contact_at - entry_started_at
    end
    return "sem tempo médio" if seconds.empty?

    duration_label(seconds.sum.to_f / seconds.size)
  end

  def duration_label(seconds)
    seconds = seconds.to_f.round
    return "#{seconds} seg" if seconds < 60

    minutes = (seconds / 60.0).round
    minutes < 60 ? "#{minutes} min" : "#{(minutes / 60.0).round(1)} h"
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

  def scoped_public_navigation_events
    @scoped_public_navigation_events ||= begin
      tenant_id = current_tenant.id
      PublicNavigationEvent
        .left_outer_joins(:habitation, :lead)
        .where(
          "public_navigation_events.tenant_id = :tenant_id OR habitations.tenant_id = :tenant_id OR leads.tenant_id = :tenant_id",
          tenant_id: tenant_id
        )
    end
  end

  def site_events_for_badges
    @site_events_for_badges ||= scoped_public_navigation_events.where("public_navigation_events.occurred_at >= ?", dashboard_window_start)
  end

  def site_event_badge_counts
    @site_event_badge_counts ||= Rails.cache.fetch(
      ["dashboard-site-event-badges-v1", current_tenant.id, @dashboard_period],
      expires_in: DASHBOARD_AGGREGATE_CACHE_EXPIRATION
    ) do
      site_events_for_badges
        .where(name: %w[page_view property_view property_whatsapp_click property_phone_click lead_form_submitted])
        .group(:name)
        .count
    end
  end

  def site_top_pages(site_events)
    site_events
      .where(name: %w[page_view property_view])
      .where.not(path: [nil, ""])
      .group(:path)
      .count
      .map do |path, count|
        {
          label: path,
          value: count,
          detail: path.start_with?("/imoveis") ? "página de imóvel/listagem" : "página pública",
          tone: "blue",
          path: path
        }
      end
      .sort_by { |row| [-row[:value].to_i, row[:label].to_s] }
      .first(6)
  end

  def site_top_properties(site_events)
    counts = site_events
      .where(name: %w[property_view property_whatsapp_click lead_form_submitted])
      .where.not(habitation_id: nil)
      .group(:habitation_id)
      .count
    return [] if counts.empty?

    properties = current_tenant.habitations
      .where(id: counts.keys)
      .pluck(:id, :codigo, :titulo_anuncio, :nome_empreendimento)
      .index_by(&:first)

    counts.map do |habitation_id, count|
      property = properties[habitation_id]
      next unless property

      _id, codigo, title, development = property
      {
        label: [codigo, title.presence || development].compact_blank.join(" · "),
        value: count,
        detail: "sinais públicos no período",
        tone: "green",
        path: admin_habitation_path(habitation_id)
      }
    end.compact.sort_by { |row| [-row[:value].to_i, row[:label].to_s] }.first(6)
  end

  def site_search_filters(site_events)
    rows = Hash.new { |hash, key| hash[key] = Hash.new(0) }
    site_events
      .where(name: %w[property_search search_no_results])
      .where.not(search_params: {})
      .order(occurred_at: :desc)
      .limit(1_000)
      .pluck(:search_params)
      .each do |payload|
        payload.to_h.each do |key, value|
          next if key.to_s.in?(%w[controller action page])
          normalized_value = Array(value).compact_blank.join(", ").presence || value.to_s.presence
          next if normalized_value.blank?

          rows[key.to_s][normalized_value] += 1
        end
      end

    rows.flat_map do |key, values|
      values.map do |value, count|
        {
          label: "#{key.humanize}: #{value}",
          value: count,
          detail: "busca/filtro usado no site",
          tone: "amber",
          path: habitations_path(key => value)
        }
      end
    end.sort_by { |row| [-row[:value].to_i, row[:label].to_s] }.first(8)
  end

  def site_conversion_funnel(site_events)
    stages = [
      {
        key: "home",
        label: "Home",
        detail: "Sessões que passaram pela página inicial",
        relation: site_events.where(name: "page_view", path: ["/", "/home"])
      },
      {
        key: "listing",
        label: "Listagem/busca",
        detail: "Sessões com listagem, busca ou filtro",
        relation: site_events.where(
          "public_navigation_events.name = :search OR public_navigation_events.path LIKE :listing_path",
          search: "property_search",
          listing_path: "/imoveis%"
        )
      },
      {
        key: "detail",
        label: "Detalhe",
        detail: "Sessões que abriram imóvel",
        relation: site_events.where(name: "property_view")
      },
      {
        key: "contact",
        label: "Contato",
        detail: "Sessões com WhatsApp, telefone ou formulário",
        relation: site_events.where(name: %w[property_whatsapp_click property_phone_click lead_form_submitted])
      }
    ]

    previous_count = nil
    stages.map do |stage|
      count = stage[:relation].distinct.count(:public_navigation_session_id)
      row = stage.except(:relation).merge(
        value: count,
        conversion_rate: previous_count.nil? ? nil : percentage(count, previous_count),
        tone: count.positive? ? "blue" : "gray"
      )
      previous_count = count
      row
    end
  end

  def site_home_section_clicks(site_events)
    rows = site_events
      .where(name: "home_section_click")
      .where("public_navigation_events.metadata ? 'home_section_id'")
      .group(
        Arel.sql("public_navigation_events.metadata->>'home_section_id'"),
        Arel.sql("public_navigation_events.metadata->>'home_section_title'"),
        Arel.sql("public_navigation_events.metadata->>'home_section_type'")
      )
      .count

    rows.map do |(section_id, title, section_type), count|
      {
        label: title.presence || "Seção #{section_id}",
        value: count,
        detail: HomeSection::SECTION_TYPE_LABELS.fetch(section_type.to_s, section_type.to_s.humanize.presence || "Seção da home"),
        tone: "blue",
        path: root_path
      }
    end.sort_by { |row| [-row[:value].to_i, row[:label].to_s] }.first(6)
  end
end
