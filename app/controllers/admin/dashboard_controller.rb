class Admin::DashboardController < Admin::BaseController
  include DeviceRequest

  DASHBOARD_SECTIONS = %w[charts acquisition funnel status service rankings operations support site].freeze
  DASHBOARD_TABS = %w[overview leads properties site field].freeze
  DASHBOARD_PERIODS = [7, 30, 90].freeze
  OVERVIEW_CACHE_EXPIRATION = 2.minutes
  DASHBOARD_AGGREGATE_CACHE_EXPIRATION = 5.minutes
  CONTACT_ACTIVITY_KINDS = %w[
    accepted note whatsapp_out appointment_created appointment_done
    proposal_created proposal_sent proposal_viewed proposal_aceita proposal_recusada
  ].freeze

  before_action :require_dashboard_admin!
  before_action :set_dashboard_context

  def index
    load_overview_slice
    load_rankings_slice if @dashboard_tab == "leads"
  end

  def section
    section_name = params[:section].to_s
    raise ActiveRecord::RecordNotFound unless DASHBOARD_SECTIONS.include?(section_name)

    unless turbo_frame_request?
      redirect_to admin_root_path(dashboard_section_redirect_params(section_name))
      return
    end

    @dashboard_tab = "all" if params[:tab].blank?
    send("load_#{section_name}_slice")
    render partial: "admin/dashboard/sections/#{section_name}", layout: false
  end

  private

  def dashboard_section_redirect_params(section_name)
    redirect_params = { period: @dashboard_period }
    redirect_params[:tab] = section_name if DASHBOARD_TABS.include?(section_name)
    redirect_params[:tab] ||= params[:tab].to_s.presence_in(DASHBOARD_TABS)
    redirect_params[:broker_id] = @dashboard_broker_id if @dashboard_broker_id.present?
    redirect_params
  end

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
    @field_feature_enabled = FieldFeatureGate.field_checkin_enabled?(tenant: current_tenant)
    requested_tab = params[:tab].to_s.presence_in(DASHBOARD_TABS) || "overview"
    @dashboard_tab = requested_tab == "field" && !@field_feature_enabled ? "overview" : requested_tab
    @dashboard_updated_at = Time.current
    @dashboard_window_start = dashboard_window_start
    @first_contact_sla_hours = LeadSetting.instance(tenant: current_tenant).first_contact_sla_hours_value
  end

  # Os ~18 counts do overview rodavam em TODA visita ao dashboard. KPIs de
  # visão geral toleram atraso curto — cache por conta+usuário (o escopo
  # visível depende do usuário). As seções (charts/funnel/...) seguem ao vivo.
  def load_overview_slice
    metrics = Rails.cache.fetch(
      ["dashboard-overview-v6", current_tenant.id, current_admin_user.id, @dashboard_period, @dashboard_broker_id],
      expires_in: OVERVIEW_CACHE_EXPIRATION
    ) { compute_overview_metrics }
    metrics.each { |name, value| instance_variable_set("@#{name}", value) }
    @operational_questions = build_operational_questions
    @decision_questions = @operational_questions.select { |question| question[:attention] }
    @health_questions = @operational_questions.reject { |question| question[:attention] }
    @overview_investigations = build_overview_investigations
    @recommended_actions = build_recommended_actions
    @dashboard_tab_badges = build_dashboard_tab_badges
    @dashboard_ai_diagnosis = build_dashboard_ai_diagnosis
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

    @leads_total = @lead_scope.count
    @new_leads = @lead_scope.where(status: [Lead.default_status, nil]).count
    @leads_today = @lead_scope.where("created_at >= ?", beginning).count
    @leads_last_7_days = @lead_scope.where("created_at >= ?", 7.days.ago).count
    @current_period_leads = @lead_scope.where("created_at >= ?", dashboard_window_start).count
    @previous_period_leads = @lead_scope.where(created_at: previous_dashboard_window).count
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
      .where(attention_leads_sql)
      .count
    @no_first_contact_leads = no_first_contact_scope.count
    @sla_overdue_leads = no_first_contact_scope.where("leads.created_at < ?", first_contact_sla_hours.hours.ago).count
    @avg_first_contact_minutes = average_first_contact_minutes
    @pending_whatsapp_conversations = pending_whatsapp_reply_scope.count
    @avg_whatsapp_response_minutes = average_whatsapp_response_minutes

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
    result = lead_acquisition_result
    result.each { |name, value| instance_variable_set("@acquisition_#{name}", value) }
    @lost_money_rows = lost_money_rows
  end

  def load_funnel_slice
    @commercial_funnel_rows = commercial_funnel_rows
    @stage_time_rows = stage_time_rows
    @stage_loss_rows = stage_loss_rows
    @lead_temperature_rows = lead_temperature_rows
    @stage_reopen_rows = stage_reopen_rows
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

  def load_service_slice
    @service_whatsapp_kpis = {
      pending_reply: pending_whatsapp_reply_scope.count,
      unread: dashboard_whatsapp_conversation_scope.unread.count,
      avg_response_minutes: average_whatsapp_response_minutes
    }
    @service_sla_rows = service_sla_rows
    @service_whatsapp_rows = service_whatsapp_rows
    @service_campaign_rows = service_campaign_rows
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

  def first_contact_sla_hours
    @first_contact_sla_hours || LeadSetting::DEFAULT_FIRST_CONTACT_SLA_HOURS
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

  def scoped_dashboard_catalog_habitations
    current_tenant.habitations.where(
      "habitations.intake_origin IS NULL OR habitations.intake_origin != :broker_origin OR habitations.intake_status IN (:visible_statuses)",
      broker_origin: Habitation::INTAKE_ORIGIN_BROKER,
      visible_statuses: Habitation::CATALOG_VISIBLE_INTAKE_STATUSES
    )
  end

  def scoped_dashboard_leads
    scope = current_tenant.leads
    owner_ids = visible_owner_ids(:leads)
    scope = owner_ids.nil? ? scope : scope.where(admin_user_id: owner_ids)
    @dashboard_broker_id ? scope.where(admin_user_id: @dashboard_broker_id) : scope
  end

  def dashboard_task_scope
    current_tenant.tasks
      .operational_current
      .where(lead_id: @lead_scope.where(status: active_lead_status_values_with_blank).select(:id))
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
          path: admin_leads_path(attention_filter: "no_first_contact", start_date: dashboard_window_start.to_date.iso8601, end_date: Date.current.iso8601)
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
          path: admin_leads_path(attribution_channel: weak_paid_channel[:key], start_date: dashboard_window_start.to_date.iso8601, end_date: Date.current.iso8601)
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
            path: admin_leads_path(status: label, start_date: dashboard_window_start.to_date.iso8601, end_date: Date.current.iso8601)
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
          path: admin_leads_path(status: label, start_date: dashboard_window_start.to_date.iso8601, end_date: Date.current.iso8601)
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
          path: admin_leads_path(status: label, start_date: dashboard_window_start.to_date.iso8601, end_date: Date.current.iso8601)
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
      { label: "Sem fotos", value: without_photos, icon: "images", tone: "amber", filter: "missing_photos", path_params: { ownership: "all", somente_sem_imagens: "1" } },
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
          end_date: Date.current.iso8601,
          broker_id: @dashboard_broker_id
        )
      )
    end

    actions.sort_by { |action| [action[:priority], -action[:value].to_i] }.first(6)
  end

  def build_dashboard_ai_diagnosis
    Dashboard::AiDiagnosis.new(
      tenant: current_tenant,
      admin_user: current_admin_user,
      period: @dashboard_period,
      metrics: dashboard_ai_metrics
    ).call
  end

  def dashboard_ai_metrics
    lost_money = lost_money_rows
    property_low_progress = property_low_progress_rows
    stage_losses = stage_loss_rows
    reopens = stage_reopen_rows
    slow_stages = stage_time_rows.select { |row| row[:value].to_f > 48 }

    {
      period_days: @dashboard_period,
      leads_total: @current_period_leads,
      previous_period_leads: @previous_period_leads,
      leads_period_change: @leads_period_change,
      no_first_contact_leads: @no_first_contact_leads,
      sla_overdue_leads: @sla_overdue_leads,
      pending_whatsapp_conversations: @pending_whatsapp_conversations,
      avg_whatsapp_response_minutes: @avg_whatsapp_response_minutes,
      site_visits: site_event_badge_counts["page_view"].to_i,
      site_contacts: site_event_badge_counts.values_at("property_whatsapp_click", "property_phone_click", "lead_form_submitted").sum(&:to_i),
      lost_money_count: lost_money.sum { |row| row[:value].to_i },
      property_low_progress_count: property_low_progress.sum { |row| row[:value].to_i },
      stage_bottleneck_count: slow_stages.size + stage_losses.sum { |row| row[:value].to_i } + reopens.sum { |row| row[:value].to_i },
      top_lost_money: lost_money.first(4).map { |row| row.slice(:label, :value, :detail, :tone) },
      top_property_low_progress: property_low_progress.first(4).map { |row| row.slice(:label, :value, :detail) },
      slow_stages: slow_stages.first(4).map { |row| row.slice(:label, :value, :detail) },
      stage_losses: stage_losses.first(4).map { |row| row.slice(:label, :value, :detail) },
      stage_reopens: reopens.first(4).map { |row| row.slice(:label, :value, :detail) }
    }
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
        path: admin_leads_path(start_date: dashboard_window_start.to_date.iso8601, end_date: Date.current.iso8601)
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
      path: admin_root_path(tab: "leads", period: @dashboard_period, broker_id: @dashboard_broker_id),
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
      path: admin_root_path(tab: "properties", period: @dashboard_period, broker_id: @dashboard_broker_id),
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
          attribution_channel: channel[:key],
          start_date: dashboard_window_start.to_date.iso8601,
          end_date: Date.current.iso8601,
          broker_id: @dashboard_broker_id
        )
      }
    end

    {
      question: "De onde vem a demanda útil?",
      answer: acquisition[:attribution_rate].to_f.positive? ? "#{acquisition[:attribution_rate]}% dos leads têm origem identificada." : "Origem ainda pouco rastreada neste período.",
      tone: acquisition[:unknown].to_i.positive? ? "amber" : "blue",
      icon: "signpost-split",
      path: admin_root_path(tab: "leads", period: @dashboard_period, broker_id: @dashboard_broker_id),
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
        path: admin_leads_path(attention_filter: "no_first_contact")
      },
      {
        label: "SLA #{first_contact_sla_hours}h vencido",
        value: @sla_overdue_leads,
        detail: "Entraram há mais de #{first_contact_sla_hours}h e ainda não receberam atendimento",
        tone: @sla_overdue_leads.to_i.positive? ? "red" : "green",
        path: admin_leads_path(attention_filter: "sla_overdue")
      },
      {
        label: "Sem responsável",
        value: @unassigned_open_leads,
        detail: "Leads abertos sem corretor responsável",
        tone: @unassigned_open_leads.to_i.positive? ? "red" : "green",
        path: admin_leads_path(broker_id: "unassigned", attention_filter: "requires_action")
      }
    ]
  end

  def service_whatsapp_rows
    [
      {
        label: "Aguardando resposta",
        value: @service_whatsapp_kpis[:pending_reply],
        detail: "Última mensagem é do cliente e a conversa segue aberta",
        tone: @service_whatsapp_kpis[:pending_reply].to_i.positive? ? "red" : "green",
        path: admin_whatsapp_conversations_path(filter: "pending_reply")
      },
      {
        label: "Não lidas",
        value: @service_whatsapp_kpis[:unread],
        detail: "Conversas com mensagens ainda não lidas pela equipe",
        tone: @service_whatsapp_kpis[:unread].to_i.positive? ? "amber" : "green",
        path: admin_whatsapp_conversations_path(filter: "unread")
      },
      {
        label: "Tempo médio de resposta",
        value: @service_whatsapp_kpis[:avg_response_minutes],
        detail: "Minutos entre mensagem recebida e primeira resposta enviada",
        tone: @service_whatsapp_kpis[:avg_response_minutes].to_i > 60 ? "amber" : "blue",
        path: admin_whatsapp_conversations_path
      }
    ]
  end

  def service_campaign_rows
    campaigns = current_tenant.whatsapp_campaigns.where("whatsapp_campaigns.created_at >= ?", dashboard_window_start)
    messages = current_tenant.whatsapp_campaign_messages
      .joins(:whatsapp_campaign)
      .where(whatsapp_campaigns: { id: campaigns.select(:id) })
    replied_campaigns_count = messages.where(status: "replied").distinct.count(:whatsapp_campaign_id)
    failed_count = messages.failed.count
    unhandled_replies = unhandled_campaign_replies_count(messages)
    unsubscribes = current_tenant.whatsapp_campaign_unsubscribes
      .where(whatsapp_campaign_id: campaigns.select(:id))
      .active
      .count

    [
      {
        label: "Campanhas com retorno",
        value: replied_campaigns_count,
        detail: "Campanhas do período com pelo menos uma resposta recebida",
        tone: replied_campaigns_count.positive? ? "blue" : "gray",
        path: admin_whatsapp_campaigns_path(started_on: dashboard_window_start.to_date.iso8601, ended_on: Date.current.iso8601)
      },
      {
        label: "Falhas de disparo",
        value: failed_count,
        detail: "Mensagens com falha em campanhas do período",
        tone: failed_count.positive? ? "red" : "green",
        path: admin_whatsapp_campaigns_path(status: "failed", started_on: dashboard_window_start.to_date.iso8601, ended_on: Date.current.iso8601)
      },
      {
        label: "Descadastros",
        value: unsubscribes,
        detail: "Contatos ativos fora das próximas campanhas",
        tone: unsubscribes.positive? ? "amber" : "green",
        path: admin_whatsapp_campaign_unsubscribes_path
      },
      {
        label: "Respostas não tratadas",
        value: unhandled_replies,
        detail: "Respostas que ainda não viraram atendimento/conversão",
        tone: unhandled_replies.positive? ? "red" : "green",
        path: admin_whatsapp_campaigns_path(started_on: dashboard_window_start.to_date.iso8601, ended_on: Date.current.iso8601)
      }
    ]
  end

  def unhandled_campaign_replies_count(messages)
    messages.where(status: "replied").where(
      <<~SQL.squish
        NOT EXISTS (
          SELECT 1
          FROM whatsapp_conversations conversations
          INNER JOIN whatsapp_messages outbound_messages
            ON outbound_messages.whatsapp_conversation_id = conversations.id
           AND outbound_messages.tenant_id = conversations.tenant_id
          WHERE conversations.tenant_id = whatsapp_campaign_messages.tenant_id
            AND outbound_messages.direction = 'outbound'
            AND outbound_messages.created_at > COALESCE(whatsapp_campaign_messages.replied_at, whatsapp_campaign_messages.updated_at)
            AND (
              (whatsapp_campaign_messages.lead_id IS NOT NULL AND conversations.lead_id = whatsapp_campaign_messages.lead_id)
              OR (
                NULLIF(whatsapp_campaign_messages.phone_number, '') IS NOT NULL
                AND conversations.contact_phone = whatsapp_campaign_messages.phone_number
              )
            )
        )
      SQL
    ).count
  end

  def broker_attention_rows
    counts = @lead_scope
      .where(status: active_lead_status_values_with_blank)
      .where(attention_leads_sql)
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
    period_scope = @lead_scope.where("leads.created_at >= ?", dashboard_window_start).where.not(property_id: nil)
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

    properties = current_tenant.habitations
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
          end_date: Date.current.iso8601
        )
      }
    end.compact.sort_by { |row| [-row[:value].to_i, row[:label].to_s] }.first(5)
  end

  def property_low_progress_rows
    @property_low_progress_rows ||= begin
      period_scope = @lead_scope.where("leads.created_at >= ?", dashboard_window_start).where.not(property_id: nil)
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
          properties = current_tenant.habitations
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
                end_date: Date.current.iso8601
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
      path: admin_root_path(tab: "leads", period: @dashboard_period, broker_id: @dashboard_broker_id),
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
      (pipeline_statuses.presence || Lead::LEGACY_STATUSES - [Lead.status_value(:descartado), Lead.status_value(:concluido)]).uniq
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
    count = @lead_scope
      .where(status: active_lead_status_values_with_blank)
      .where("leads.tags @> ?", [tag].to_json)
      .where("leads.updated_at < ?", stale_before)
      .count
    {
      label: label,
      value: count,
      detail: "tag #{tag} sem atualização desde #{I18n.l(stale_before.to_date)}",
      tone: count.positive? ? tone : "green",
      path: admin_leads_path(tags: [tag], attention_filter: "stalled")
    }
  end

  def formatted_currency(value)
    number = value.to_f
    formatted = format("%.2f", number).tr(".", ",")
    "R$ #{formatted.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1.')}"
  rescue TypeError
    "R$ 0,00"
  end

  def attention_leads_sql
    ActiveRecord::Base.sanitize_sql_array([
      <<~SQL.squish,
        leads.status = ?
        OR leads.admin_user_id IS NULL
        OR EXISTS (
          SELECT 1
          FROM tasks attention_tasks
          WHERE attention_tasks.tenant_id = leads.tenant_id
            AND attention_tasks.lead_id = leads.id
            AND attention_tasks.status = 'pendente'
            AND attention_tasks.due_at IS NOT NULL
            AND attention_tasks.due_at < ?
        )
        OR (
          leads.created_at < ?
          AND NOT EXISTS (
            SELECT 1
            FROM lead_activities contact_activities
            WHERE contact_activities.lead_id = leads.id
              AND contact_activities.kind IN (?)
          )
        )
      SQL
      Lead.status_value(:represado),
      Time.current,
      first_contact_sla_hours.hours.ago,
      CONTACT_ACTIVITY_KINDS
    ])
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
      ["dashboard-lead-acquisition-v2", current_tenant.id, current_admin_user.id, @dashboard_period, @dashboard_broker_id],
      expires_in: DASHBOARD_AGGREGATE_CACHE_EXPIRATION
    ) do
      Dashboard::LeadAcquisitionQuery.new(
        scope: @lead_scope,
        starts_at: dashboard_window_start,
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
      .merge(@lead_scope.where("leads.created_at >= ?", dashboard_window_start))
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
    period_scope = @lead_scope.where("leads.created_at >= ?", dashboard_window_start)
    counts = period_scope
      .where.not(admin_user_id: nil).group(:admin_user_id).count
    closed_status = Lead.status_value(:concluido)
    closed_counts = period_scope
      .where(status: closed_status).where.not(admin_user_id: nil).group(:admin_user_id).count
    attention_counts = @lead_scope
      .where(status: active_lead_status_values_with_blank)
      .where(attention_leads_sql)
      .where.not(admin_user_id: nil)
      .group(:admin_user_id)
      .count
    visit_counts = Appointment
      .joins(:lead)
      .merge(period_scope)
      .where(kind: "visita")
      .where.not(leads: { admin_user_id: nil })
      .group("leads.admin_user_id")
      .distinct
      .count("appointments.lead_id")
    proposal_counts = Proposal
      .joins(:lead)
      .merge(period_scope)
      .where.not(status: "rascunho")
      .where.not(leads: { admin_user_id: nil })
      .group("leads.admin_user_id")
      .distinct
      .count("proposals.lead_id")
    broker_ids = (counts.keys | attention_counts.keys).compact
    names = current_tenant.admin_users.where(id: broker_ids).pluck(:id, :name).to_h

    broker_ids.map do |broker_id|
      total = counts[broker_id].to_i
      closed = closed_counts[broker_id].to_i
      visits = visit_counts[broker_id].to_i
      proposals = proposal_counts[broker_id].to_i
      attention = attention_counts[broker_id].to_i
      {
        id: broker_id,
        name: names[broker_id] || "Corretor",
        total: total,
        visits: visits,
        proposals: proposals,
        closed: closed,
        attention: attention,
        conversion: percentage(closed, total),
        opportunity_rate: percentage([visits, proposals, closed].max, total)
      }
    end.sort_by { |row| [-row[:attention], -row[:closed], -row[:proposals], -row[:visits], -row[:total]] }.first(6)
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
