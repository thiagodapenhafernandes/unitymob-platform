require "csv"
require "cgi"
require "zlib"

class Admin::LeadsController < Admin::BaseController
  # Kanban carrega em pequenos lotes por coluna para manter a tela responsiva.
  KANBAN_COLUMN_PAGE_SIZE = 5
  # Lista PWA de leads: carrega em lotes por aba (scroll infinito).
  PWA_LEAD_LIST_PAGE_SIZE = 15
  # Kanban PWA: mostra um recorte curto por etapa para manter a navegação leve.
  PWA_LEAD_KANBAN_COLUMN_SIZE = 5
  HIDDEN_KANBAN_STATUSES = ["Aguardando Aceite", "Represado", "Concluido"].freeze
  # Origem default do lead cadastrado na mão: separa do que veio de site/portal.
  MANUAL_LEAD_ORIGIN = "Cadastro manual".freeze
  CONTACT_KIND_LABELS = {
    "ligacao" => "Ligação",
    "whatsapp" => "WhatsApp",
    "email" => "E-mail",
    "visita" => "Visita",
    "nota" => "Anotação interna",
    "note" => "Anotação interna"
  }.freeze
  CONTACT_RESULT_LABELS = {
    "nao_respondeu" => "Não respondeu",
    "falou_com_cliente" => "Falou com cliente",
    "retornar_depois" => "Retornar depois",
    "sem_interesse" => "Sem interesse"
  }.freeze
  CONTACT_ACTIVITY_KINDS = %w[
    accepted note whatsapp_out appointment_created appointment_done
    proposal_created proposal_sent proposal_viewed proposal_aceita proposal_recusada
  ].freeze
  REPORT_XLSX_MIME = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet".freeze
  REPORT_XLSX_HEADERS = [
    "Nome do cliente",
    "Email do cliente",
    "Telefone formatado",
    "Canal/Fonte",
    "Usuário responsável atual",
    "Lead atendido pelo bolsão?",
    "Título do imóvel"
  ].freeze
  REPORT_XLSX_COLUMN_WIDTHS = [22.55, 20, 17.89, 12, 18, 11, 30].freeze
  EXTERNAL_SCHEDULE_KIND = "external_scheduled_action".freeze
  EXTERNAL_SCHEDULE_DATE_SQL = <<~SQL.squish.freeze
    NULLIF(COALESCE(
      lead_activities.metadata #>> '{raw,schedulated_action_date}',
      lead_activities.metadata #>> '{raw,due_at}',
      lead_activities.metadata #>> '{raw,scheduled_at}',
      lead_activities.metadata #>> '{raw,date}',
      lead_activities.metadata #>> '{raw,datetime}',
      lead_activities.metadata ->> 'due_at'
    ), '')::timestamptz
  SQL
  EXTERNAL_SCHEDULE_TEXT_SQL = <<~SQL.squish.freeze
    LOWER(CONCAT_WS(' ',
      lead_activities.metadata #>> '{raw,schedulated_action_name}',
      lead_activities.metadata #>> '{raw,schedulated_action_type_alias}',
      lead_activities.metadata #>> '{raw,name}',
      lead_activities.metadata #>> '{raw,title}',
      lead_activities.metadata #>> '{raw,alias}',
      lead_activities.metadata #>> '{raw,type}',
      lead_activities.metadata ->> 'title'
    ))
  SQL
  EXTERNAL_SCHEDULE_STATUS_SQL = "LOWER(COALESCE(lead_activities.metadata #>> '{raw,status}', lead_activities.metadata #>> '{raw,status_name}', lead_activities.metadata #>> '{raw,done}', ''))".freeze
  EXTERNAL_VISIT_SCHEDULE_SQL = "(#{EXTERNAL_SCHEDULE_TEXT_SQL} LIKE '%visita%' OR #{EXTERNAL_SCHEDULE_TEXT_SQL} LIKE '%scheduled_visit%' OR #{EXTERNAL_SCHEDULE_TEXT_SQL} LIKE '%reuniao%')".freeze
  EXTERNAL_CLOSED_SCHEDULE_SQL = "(#{EXTERNAL_SCHEDULE_STATUS_SQL} LIKE '%cancel%' OR #{EXTERNAL_SCHEDULE_STATUS_SQL} LIKE '%conclu%' OR #{EXTERNAL_SCHEDULE_STATUS_SQL} LIKE '%finalizado%' OR #{EXTERNAL_SCHEDULE_STATUS_SQL} = 'true')".freeze
  LEAD_FILTER_TEXT_SQL = <<~SQL.squish.freeze
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
  LEAD_SEARCH_COLUMNS = %w[
    name email phone client_name client_email client_phone origin product
  ].freeze
  LEAD_PRICE_SQL = <<~SQL.squish.freeze
    COALESCE(
      NULLIF(habitations.valor_venda_cents, 0) / 100.0,
      NULLIF(habitations.valor_locacao_cents, 0) / 100.0,
      CASE
        WHEN NULLIF(regexp_replace(COALESCE(
          leads.attribution_data #>> '{product,price_float}',
          leads.other_information #>> '{external_lead_payload,attributes,product,price_float}',
          leads.other_information #>> '{webhook_payload,price}',
          leads.other_information #>> '{webhook_payload,valor}',
          leads.other_information #>> '{webhook_payload,value}',
          ''
        ), '[^0-9\\.]', '', 'g'), '') ~ '^[0-9]+(\\.[0-9]+)?$'
        THEN NULLIF(regexp_replace(COALESCE(
          leads.attribution_data #>> '{product,price_float}',
          leads.other_information #>> '{external_lead_payload,attributes,product,price_float}',
          leads.other_information #>> '{webhook_payload,price}',
          leads.other_information #>> '{webhook_payload,valor}',
          leads.other_information #>> '{webhook_payload,value}',
          ''
        ), '[^0-9\\.]', '', 'g'), '')::numeric
      END
    )
  SQL
  BUSINESS_FILTERS = {
    "sale" => "(#{LEAD_FILTER_TEXT_SQL} LIKE '%venda%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%compra%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%comprar%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%sale%')",
    "rental" => "(#{LEAD_FILTER_TEXT_SQL} LIKE '%loca%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%aluguel%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%alugar%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%rental%')",
    "launch" => "(#{LEAD_FILTER_TEXT_SQL} LIKE '%lanc%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%lanç%')",
    "capture" => "(#{LEAD_FILTER_TEXT_SQL} LIKE '%capt%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%proprietar%')"
  }.freeze
  CHANNEL_FILTERS = {
    "showroom" => "(#{LEAD_FILTER_TEXT_SQL} LIKE '%showroom%')",
    "phone" => "(#{LEAD_FILTER_TEXT_SQL} LIKE '%telefone%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%phone%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%ligacao%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%ligação%')",
    "social" => "(#{LEAD_FILTER_TEXT_SQL} LIKE '%facebook%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%instagram%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%meta%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%rede social%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%social%')",
    "whatsapp" => "(#{LEAD_FILTER_TEXT_SQL} LIKE '%whatsapp%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%whats%')",
    "internet" => "(#{LEAD_FILTER_TEXT_SQL} LIKE '%internet%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%site%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%google%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%portal%')"
  }.freeze
  PwaExternalSchedule = Struct.new(:lead_id, :title, :kind, :due_at, :task_id, keyword_init: true) do
    alias starts_at due_at

    def atrasada?
      kind != "visita" && due_at.present? && due_at < Time.current
    end
  end

  before_action -> { check_permission!(:view, :leads) }
  before_action -> { check_permission!(:view, :lead_reports) }, only: [:report]
  # Editar exige permissão própria: antes o update só pedia :view + escopo do
  # registro, então quem enxergasse o lead podia alterá-lo (inclusive arrastar
  # no kanban). O recorte por registro continua vindo do authorize_lead_access!.
  before_action -> { check_permission!(:edit, :leads) }, only: [:update]
  before_action -> { check_permission!(:create, :leads) }, only: [:new, :create]
  helper_method :can_destroy_lead?, :can_assign_lead_owner?, :lead_contact_kind_label, :lead_contact_result_label, :lead_unsuccessful_attempt_count
  before_action :set_lead, only: [:show, :update, :destroy, :toggle_favorite, :log_contact, :reprocess_interest, :simulate_interest, :interest_intelligence, :open_whatsapp_conversation, :activate_whatsapp_template, :share_properties, :suggest_properties, :archive, :close_deal, :schedule_activity]
  before_action :authorize_lead_access!, only: [:show, :update, :destroy, :toggle_favorite, :log_contact, :reprocess_interest, :simulate_interest, :interest_intelligence, :open_whatsapp_conversation, :activate_whatsapp_template, :share_properties, :suggest_properties, :archive, :close_deal, :schedule_activity]
  before_action :load_lead_pipeline_context, only: [:index, :kanban_column, :pwa_leads_page, :report, :new, :create, :show, :update]
  before_action :load_origin_options, only: [:index, :kanban_column, :pwa_leads_page, :report, :new, :create, :show, :update]

  def index
    assign_lead_filter_state
    @view_mode = resolve_view_mode

    unfiltered_scope = lead_scope_for_current_user
    filtered_scope = filtered_lead_scope_for_current_user
    @desktop_lead_tab = params[:lead_tab].presence_in(%w[todo visits future favorites all]) || "all"
    list_filtered_scope = hide_discarded_from_list_scope(filtered_scope)
    @desktop_tab_counts = lead_tab_counts_for(list_filtered_scope)
    lead_scope = lead_scope_for_tab(filtered_scope, @desktop_lead_tab)
    list_scope = lead_scope_for_tab(list_filtered_scope, @desktop_lead_tab)

    stats_scope = list_scope.reorder(nil)
    @total_leads = stats_scope.count
    @new_leads = stats_scope.where(status: status_filter_values_for(Lead.status_value(:novo, tenant: current_tenant))).count
    @in_service_leads = stats_scope.where(status: Lead.status_value("Em Atendimento", tenant: current_tenant)).count
    @unassigned_leads = stats_scope.where(admin_user_id: nil).count
    @status_counts = stats_scope.group(:status).count
    @origin_counts = lead_scope_for_current_user.reorder(nil).where.not(origin: [nil, ""]).group(:origin).count

    lead_scope = lead_scope.includes(:admin_user, lead_labelings: :lead_label).order(created_at: :desc)
    list_scope = list_scope.includes(:admin_user, lead_labelings: :lead_label).order(created_at: :desc)

    @lead_statuses = lead_statuses_for_kanban(lead_scope)
    @leads_by_status = @lead_statuses.index_with { |status| [] }
    # Primeiro lote por coluna DIRETO NO BANCO (janela por status): antes carregava a
    # base inteira de leads na memória a cada visita ao kanban.
    ranked = lead_scope.reorder(nil).select(
      "leads.*, ROW_NUMBER() OVER (PARTITION BY leads.status ORDER BY leads.created_at DESC) AS kanban_rank"
    )
    @kanban_leads = Lead.from(ranked, :leads)
                        .where("kanban_rank <= ?", KANBAN_COLUMN_PAGE_SIZE)
                        .includes(:admin_user, lead_labelings: :lead_label)
                        .order(created_at: :desc)
                        .to_a
    @kanban_leads.each do |lead|
      status = Lead.status_value(lead.status, tenant: current_tenant)
      next if @selected_pipeline.present? && !@leads_by_status.key?(status)

      @leads_by_status[status] ||= []
      @leads_by_status[status] << lead
    end
    # Contadores da coluna = total REAL (a coluna pode estar truncada no teto).
    @lead_counts_by_status = Hash.new(0)
    lead_scope.reorder(nil).group(:status).count.each do |status, count|
      status = Lead.status_value(status, tenant: current_tenant)
      next if @selected_pipeline.present? && !@leads_by_status.key?(status)

      @lead_counts_by_status[status] += count
    end
    @lead_statuses.each { |status| @lead_counts_by_status[status] ||= 0 }
    @kanban_column_page_size = KANBAN_COLUMN_PAGE_SIZE
    @leads = list_scope.paginate(page: params[:page], per_page: 20)
    load_pwa_leads_context(filtered_scope.reorder(nil), unfiltered_scope: unfiltered_scope.reorder(nil))
    property_ids = (@kanban_leads + @leads.to_a + @pwa_leads.to_a + @pwa_kanban_leads.to_a).filter_map(&:property_id).uniq
    @properties_by_id = current_tenant.habitations.where(id: property_ids).index_by(&:id)
    @selected_lead = @kanban_leads.first || @leads.first
    @page_title = "Gerenciar Leads"
  end

  def distribution_queue
    @queue_rules = current_user_distribution_queue_rules
      .order(:name)

    @queue_agents_by_rule_id = DistributionRuleAgent
      .where(tenant_id: current_tenant.id, distribution_rule_id: @queue_rules.map(&:id))
      .includes(:admin_user)
      .order(:position, :id)
      .group_by(&:distribution_rule_id)
    @queue_positions_by_rule_id = @queue_agents_by_rule_id.transform_values do |agents|
      display_queue_position_for_agents(agents, current_admin_user.id)
    end
    @queue_agent_positions_by_id = display_queue_positions_by_agent_id(@queue_agents_by_rule_id.values.flatten)
    @best_queue_position = @queue_positions_by_rule_id.values.compact.min
    queue_rule_ids = @queue_rules.map(&:id)
    @focused_pool_lead_id = params[:lead_id].presence&.to_i
    pool_scope = current_tenant.leads
      .where(distribution_rule_id: queue_rule_ids, admin_user_id: nil, status: Lead.status_value(:waiting_acceptance))
      .includes(:distribution_rule)

    @pool_leads = if @focused_pool_lead_id.present?
      pool_scope.order(Arel.sql("CASE WHEN leads.id = #{@focused_pool_lead_id.to_i} THEN 0 ELSE 1 END, leads.created_at ASC"))
    else
      pool_scope.order(created_at: :asc)
    end
    @pool_leads_by_rule_id = @pool_leads.group_by(&:distribution_rule_id)
    @return_to_path = admin_leads_path(view: current_admin_user&.leads_view_mode.presence_in(%w[kanban list]) || "list")
    @page_title = "Bolsão"
  end

  def report
    assign_lead_filter_state
    scope = filtered_lead_scope_for_current_user.includes(:admin_user, :archive_reason, :lead_pipeline_stage).order(created_at: :asc)
    include_captacoes = params[:include_captacoes].to_s == "1"
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")

    if params[:format].to_s == "xlsx"
      send_data commercial_report_xlsx(scope, include_captacoes:),
                filename: "relatorio_leads_#{timestamp}.xlsx",
                type: REPORT_XLSX_MIME,
                disposition: "attachment"
    else
      send_data commercial_report_csv(scope, include_captacoes:),
                filename: "relatorio_leads_#{timestamp}.csv",
                type: "text/csv; charset=utf-8"
    end
  end

  def kanban_column
    assign_lead_filter_state

    status = Lead.status_value(params[:status], tenant: current_tenant)
    offset = [params[:offset].to_i, 0].max
    desktop_tab = params[:lead_tab].presence_in(%w[todo visits future favorites all]) || "all"
    lead_scope = lead_scope_for_tab(filtered_lead_scope_for_current_user, desktop_tab).where(leads: { status: status_filter_values_for(status) })
    total = lead_scope.reorder(nil).count
    leads = lead_scope
            .includes(:admin_user, lead_labelings: :lead_label)
            .order(created_at: :desc)
            .offset(offset)
            .limit(KANBAN_COLUMN_PAGE_SIZE)
            .to_a
    property_ids = leads.filter_map(&:property_id).uniq
    @properties_by_id = current_tenant.habitations.where(id: property_ids).index_by(&:id)
    return_to_path = safe_return_path(params[:return_to]) || admin_leads_path(request.query_parameters.except("offset", "return_to").merge(view: "kanban"))

    html = leads.map do |lead|
      render_to_string(
        partial: "admin/leads/kanban_card",
        formats: [:html],
        locals: {
          lead: lead,
          property: (@properties_by_id[lead.property_id] if lead.property_id.present?),
          status_tone: kanban_status_tone,
          return_to_path: return_to_path
        }
      )
    end.join
    next_offset = offset + leads.size

    render json: {
      html: html,
      next_offset: next_offset,
      has_more: next_offset < total,
      loaded_count: leads.size,
      total: total
    }
  end

  def pwa_leads_page
    assign_lead_filter_state

    tab = params[:mobile_tab].presence_in(%w[todo visits future favorites all]) || "todo"
    offset = [params[:offset].to_i, 0].max
    base_scope = hide_discarded_from_list_scope(filtered_lead_scope_for_current_user.where(admin_user_id: current_admin_user&.id))
    lead_scope = pwa_lead_scope_for_tab(base_scope, tab)
    total = lead_scope.reorder(nil).count
    leads = lead_scope
            .includes(:admin_user, lead_labelings: :lead_label)
            .order(updated_at: :desc, created_at: :desc)
            .offset(offset)
            .limit(PWA_LEAD_LIST_PAGE_SIZE)
            .to_a

    property_ids = leads.filter_map(&:property_id).uniq
    @properties_by_id = current_tenant.habitations.where(id: property_ids).index_by(&:id)
    load_pwa_lead_activity_context(leads)

    html = leads.map do |lead|
      render_to_string(partial: "admin/leads/pwa_lead_card", formats: [:html], locals: { lead: lead })
    end.join
    next_offset = offset + leads.size

    render json: {
      html: html,
      next_offset: next_offset,
      has_more: next_offset < total,
      loaded_count: leads.size,
      total: total
    }
  end

  def show
    @page_title = "Lead: #{@lead.name}"
    @return_to_path = safe_return_path(params[:return_to])
    @property = current_tenant.habitations.find_by(id: @lead.property_id)
    @lead_audit_logs = @lead.lead_audit_logs.includes(:admin_user).recent.limit(80)

    # Workspace comercial: timeline unificada + tarefas + propostas + próxima ação
    @push_delivery_events = push_delivery_events_for(@lead)
    @timeline = lead_timeline_events_for(@lead, @push_delivery_events)
    @contact_history_activities = @lead.activities.where(kind: "note").recent.limit(40)
    @tasks = @lead.tasks.includes(:admin_user).ordered.limit(50)
    @actionable_tasks = actionable_lead_tasks(@tasks)
    @next_task = @actionable_tasks.select(&:pendente?).find { |task| task.due_at.present? } ||
                 @actionable_tasks.find(&:pendente?)
    @appointments = @lead.appointments.upcoming.limit(20)
    @proposals = @lead.proposals.ordered.limit(20)
    load_proposal_modal_context
    @archive_reason_options = archive_reason_options_for(@lead)
    @funnel_statuses = Lead.status_options
    load_lead_whatsapp_context
    @property_share_collections = @lead.ai_property_share_collections.includes(:admin_user, :habitations).order(created_at: :desc).limit(12)
    @shared_interest_property_ids = @lead.shared_property_ids
    @shared_interest_property_statuses = @lead.shared_property_statuses
    @interest_settings = InterestIntelligence::Settings.current
    load_lead_favorite_context
  end

  def toggle_favorite
    favorite = current_admin_user.lead_favorites.find_by(lead: @lead)
    if favorite
      favorite.destroy
      notice = "Lead removido dos favoritos."
    else
      current_admin_user.lead_favorites.create!(lead: @lead, tenant: current_tenant)
      notice = "Lead adicionado aos favoritos."
    end

    redirect_back fallback_location: admin_lead_path(@lead), notice: notice
  end

  # Destino do clique na notificação push de novo lead. Decide no momento do
  # clique (o tempo passa entre receber e tocar): se o lead ainda é do corretor
  # (dentro do prazo do pocket), aceita e abre conforme a config global; se já
  # foi redistribuído (prazo estourado), mostra a tela de tempo esgotado.
  def attend
    @lead = current_tenant.leads.find_by(id: params[:id])
    return render :attend_expired, status: :ok unless @lead

    # Shark Tank: lead sem dono em "Aguardando Aceite" — corrida pra reivindicar.
    if @lead.admin_user_id.nil? && shark_tank_open?(@lead)
      claimable_rule_ids = current_user_distribution_queue_rules.where(id: @lead.distribution_rule_id).pluck(:id)
      unless claimable_rule_ids.any?
        @attend_reason = :taken
        return render :attend_expired, status: :ok
      end

      claimed = Lead.claim_for_rules!(@lead.id, current_admin_user&.id, claimable_rule_ids)
      @lead.reload
      if claimed
        @lead.distribution_rule&.mark_agent_served!(current_admin_user.id)
        @lead.activities.create(kind: "accepted", metadata: { by: current_admin_user&.name, shark_tank: true }.compact)
      end

      unless @lead.admin_user_id == current_admin_user&.id
        @attend_reason = :taken
        return render :attend_expired, status: :ok
      end

      return open_attended_lead(@lead)
    end

    unless lead_still_mine?(@lead)
      @attend_reason = :taken if @lead.admin_user_id.present? && @lead.admin_user_id != current_admin_user&.id
      return render :attend_expired, status: :ok
    end

    unless accept_lead!(@lead)
      # Perdeu a corrida pro PocketExpiration entre a leitura e o clique:
      # o lead já foi redistribuído — mesma UX do prazo esgotado.
      @attend_reason = :taken if @lead.admin_user_id.present? && @lead.admin_user_id != current_admin_user&.id
      return render :attend_expired, status: :ok
    end

    open_attended_lead(@lead)
  end

  def new
    @lead = current_tenant.leads.new(
      lead_pipeline: @selected_pipeline,
      lead_pipeline_stage: @selected_pipeline&.default_stage,
      status: Lead.default_status(tenant: current_tenant, pipeline: @selected_pipeline),
      origin: MANUAL_LEAD_ORIGIN,
      admin_user_id: current_admin_user&.id
    )
    @page_title = "Novo lead"
  end

  def create
    @lead = current_tenant.leads.new(new_lead_params)
    @lead.admin_user_id = resolved_owner_id_for_new_lead

    if @lead.save
      LeadActivity.log!(
        lead: @lead,
        kind: "created",
        metadata: { by: current_admin_user&.name, origin: @lead.origin, owner: @lead.admin_user&.name }.compact
      )
      redirect_to admin_lead_path(@lead), notice: lead_created_notice
    else
      @page_title = "Novo lead"
      render :new, status: :unprocessable_entity
    end
  end

  def log_contact
    kind = params[:contact_kind].presence_in(CONTACT_KIND_LABELS.keys) || "nota"
    result = params[:contact_result].presence_in(CONTACT_RESULT_LABELS.keys)
    body = params[:body].to_s.strip
    if body.blank?
      return redirect_back fallback_location: admin_lead_path(@lead), alert: "Descreva o contato antes de salvar."
    end
    if LeadActivity::CONTACT_ATTEMPT_KINDS.include?(kind) && result.blank?
      return redirect_back fallback_location: admin_lead_path(@lead), alert: "Informe o resultado da tentativa de contato."
    end
    result = nil unless LeadActivity::CONTACT_ATTEMPT_KINDS.include?(kind)

    LeadActivity.log!(
      lead: @lead,
      kind: "note",
      metadata: { contact_kind: kind, contact_result: result, body: body, by: current_admin_user&.name, admin_user_id: current_admin_user&.id }.compact
    )
    redirect_back fallback_location: admin_lead_path(@lead), notice: "Contato registrado."
  end

  def update
    previous_status = @lead.status
    attributes = lead_params
    unless allowed_stage_transition?(attributes)
      @lead.errors.add(:lead_pipeline_stage, "não está disponível como próxima etapa")
      return respond_to do |format|
        format.html do
          load_show_context
          render :show, status: :unprocessable_entity
        end
        format.turbo_stream do
          load_show_context
          render :show, formats: [:html], status: :unprocessable_entity
        end
        format.json { render json: { error: @lead.errors.full_messages.to_sentence }, status: :unprocessable_entity }
      end
    end

    unless allowed_lead_qualification?(attributes)
      @lead.errors.add(:base, "Esta qualificação não está disponível para a etapa atual.")
      return respond_to do |format|
        format.html do
          load_show_context
          render :show, status: :unprocessable_entity
        end
        format.turbo_stream do
          load_show_context
          render :show, formats: [:html], status: :unprocessable_entity
        end
        format.json { render json: { error: @lead.errors.full_messages.to_sentence }, status: :unprocessable_entity }
      end
    end

    if @lead.update(attributes)
      if @lead.saved_change_to_status?
        LeadActivity.log!(lead: @lead, kind: "status_change", metadata: { from: previous_status, to: @lead.status, by: current_admin_user&.name })
      end
      log_qualification_change! if @lead.saved_change_to_broker_qualification_status? || @lead.saved_change_to_manager_qualification_status?
      if @lead.saved_change_to_admin_user_id? && @lead.admin_user_id.present?
        Leads::NotificationDispatcher.notify_reassignment(@lead, @lead.admin_user)
      end
      respond_to do |format|
        format.html { redirect_to admin_lead_path(@lead), notice: "Lead atualizado com sucesso." }
        format.turbo_stream { redirect_to admin_lead_path(@lead), notice: "Lead atualizado com sucesso." }
        format.json do
          render json: {
            id: @lead.id,
            status: @lead.status,
            badge_class: Lead.status_badge_class(@lead.status),
            qualification_status: @lead.qualification_status_for(current_admin_user),
            qualification_label: @lead.qualification_label_for(current_admin_user),
            qualification_divergent: @lead.qualification_divergent?
          }
        end
      end
    else
      respond_to do |format|
        format.html do
          load_show_context
          render :show, status: :unprocessable_entity
        end
        format.turbo_stream do
          load_show_context
          render :show, formats: [:html], status: :unprocessable_entity
        end
        format.json { render json: { errors: @lead.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def reprocess_interest
    unless can?(:edit, :leads) || can?(:manage, :comercial) || owns_all_resource?(:leads)
      redirect_to admin_lead_path(@lead), alert: "Você não tem permissão para reprocessar a inteligência deste lead."
      return
    end

    result = InterestIntelligence::Reprocessor.call(lead: @lead, actor: current_admin_user)
    message = if result.profile_incomplete
                "Interesse reprocessado. Ainda faltam sinais suficientes para sugerir imóveis com segurança."
              else
                "Interesse reprocessado. #{result.matches.size} imóvel(is) compatível(is) encontrado(s)."
              end

    redirect_to admin_lead_path(@lead), notice: message
  end

  def simulate_interest
    load_show_context
    load_interest_intelligence
    @interest_simulation = true
    render :show
  end

  def interest_intelligence
    load_interest_intelligence

    html = render_to_string(
      partial: "admin/leads/interest_intelligence",
      formats: [:html],
      locals: {
        lead: @lead,
        profile: @interest_profile,
        profile_incomplete: @interest_profile_incomplete,
        matches: @interest_matches,
        navigation_events: @interest_navigation_events,
        property_interests: @interest_property_interests,
        settings: @interest_settings,
        simulation: false,
        embedded: true
      }
    )

    frame_id = request.headers["Turbo-Frame"].presence || view_context.dom_id(@lead, :interest_intelligence)
    render html: %(<turbo-frame id="#{ERB::Util.html_escape(frame_id)}">#{html}</turbo-frame>).html_safe, layout: false
  end

  def open_whatsapp_conversation
    check_permission!(:view, :whatsapp_inbox)

    conversation = find_or_create_whatsapp_conversation_for!(@lead)
    route_options = { lead_id: @lead.id }
    route_options[:workspace] = "focus" if params[:workspace].to_s == "focus"
    destination = admin_whatsapp_conversation_path(conversation, route_options)
    redirect_to destination
  rescue ArgumentError => e
    redirect_to admin_lead_path(@lead), alert: e.message
  end

  def activate_whatsapp_template
    check_permission!(:manage, :whatsapp_inbox)
    return_path = safe_return_path(params[:return_to])

    integration = WhatsappBusinessIntegration.current(current_tenant)
    template = Whatsapp::LeadActivationTemplate.for(tenant: current_tenant, integration: integration)
    unless template&.persisted? && template.approved?
      return redirect_to(return_path || admin_lead_path(@lead), alert: "Configure e aprove o template de ativação de lead na integração WhatsApp.")
    end

    conversation = find_or_create_whatsapp_conversation_for!(@lead)
    variables = Whatsapp::LeadActivationTemplate.variable_values(lead: @lead, admin_user: current_admin_user)
    message = conversation.messages.create!(
      direction: "outbound",
      status: "pending",
      msg_type: "template",
      template_name: template.name,
      body: template.render_body(variables.values_at(*variables.keys.sort_by(&:to_i))),
      admin_user: current_admin_user
    )
    attach_activation_template_header!(message)
    components = activation_template_components(template, variables, message)
    unless components.ok?
      message.update!(status: "failed", error_message: components.error.to_s.truncate(250))
      return redirect_to(return_path || admin_lead_path(@lead), alert: components.error)
    end

    message.update!(template_components: components.components)
    conversation.touch_last_message!(message)
    Whatsapp::SendMessageJob.dispatch(message.id, tenant_id: message.tenant_id)
    LeadActivity.log!(lead: @lead, kind: "whatsapp_out", metadata: { body: message.preview, by: current_admin_user&.name })

    redirect_to(return_path || admin_whatsapp_conversation_path(conversation), notice: "Template enviado e conversa ativada no inbox.")
  rescue ArgumentError => e
    redirect_to(return_path || admin_lead_path(@lead), alert: e.message)
  end

  def share_properties
    setting = PropertySetting.instance(tenant: current_tenant)
    unless setting.ai_property_search_sharing_enabled?
      return render json: { error: setting.ai_property_search_sharing_disabled_message }, status: :forbidden
    end

    ids = Array(params[:habitation_ids]).map(&:to_i).uniq.first(setting.ai_property_search_share_max_properties)
    if ids.empty?
      return render json: { error: "Selecione ao menos um imóvel para compartilhar." }, status: :unprocessable_entity
    end

    result = Ai::PropertyShareCollectionCreator.call(
      tenant: current_tenant,
      admin_user: current_admin_user,
      setting:,
      scope: current_tenant.habitations.where(id: ids),
      source: "lead_detail",
      min_count: 1,
      lead: @lead,
      expires_at: lead_share_expires_at(setting)
    )
    url = public_share_collection_url(result.collection)
    message = lead_property_share_message(result.habitations, url, setting)
    result.collection.update!(message:)
    ensure_shared_property_interests!(result.habitations)
    result.collection.record!(
      "lead_share_link_created",
      lead: @lead,
      admin_user: current_admin_user,
      metadata: {
        habitation_ids: result.habitations.map(&:id),
        expires_at: result.collection.expires_at,
        url:
      }
    )
    LeadActivity.log!(
      lead: @lead,
      kind: "property_share",
      metadata: {
        by: current_admin_user&.name,
        share_collection_id: result.collection.id,
        habitation_ids: result.habitations.map(&:id),
        expires_at: result.collection.expires_at
      }.compact
    )

    render json: {
      url:,
      count: result.habitations.size,
      message:,
      whatsapp_url: lead_share_whatsapp_url(message),
      chips_html: render_property_interest_chips(share: true)
    }
  rescue Ai::PropertyShareCollectionCreator::TooFewShareableRecords
    render json: { error: "Selecione ao menos um imóvel com status Venda ou Aluguel." }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Nenhum imóvel selecionado pode ser compartilhado." }, status: :unprocessable_entity
  end

  def suggest_properties
    result = InterestIntelligence::LeadPropertySuggestionApplicator.call(
      lead: @lead,
      tenant: current_tenant,
      admin_user: current_admin_user,
      limit: params[:limit]
    )

    if result.empty?
      message = result.profile_incomplete ? "Ainda faltam sinais suficientes para sugerir imóveis." : "Não encontrei novos imóveis compatíveis para este perfil."
      return render json: { error: message }, status: :unprocessable_entity
    end

    render json: {
      count: result.count,
      suggestions: result.matches.map { |match| property_suggestion_payload(match) },
      chips_html: render_property_interest_chips(share: true)
    }
  end

  def archive
    check_permission!(:manage, :comercial)

    reason = current_tenant.attribute_options.for_context("lead").for_category("archive_reason").find_by(id: params[:archive_reason_id])
    unless archive_reason_allowed?(reason)
      return redirect_to admin_lead_path(@lead), alert: "Este motivo não está disponível para a etapa atual."
    end

    @lead.archiving = true
    @lead.assign_attributes(
      status: Lead.status_value("Descartado", tenant: current_tenant),
      archive_reason: reason,
      archive_note: params[:archive_note],
      archived_at: Time.current,
      archived_by_admin_user: current_admin_user
    )

    if @lead.save
      LeadActivity.log!(
        lead: @lead,
        kind: "archived",
        metadata: { reason: reason&.name, note: @lead.archive_note, by: current_admin_user&.name }
      )
      redirect_to admin_lead_path(@lead), notice: "Lead arquivado."
    else
      redirect_to admin_lead_path(@lead), alert: @lead.errors.full_messages.to_sentence
    end
  end

  def close_deal
    check_permission!(:manage, :comercial)

    previous_status = @lead.status
    if @lead.update(status: Lead.status_value("Concluido", tenant: current_tenant))
      LeadActivity.log!(lead: @lead, kind: "deal_closed", metadata: { from: previous_status, by: current_admin_user&.name })
      redirect_to admin_lead_path(@lead), notice: "Negócio marcado como fechado."
    else
      redirect_to admin_lead_path(@lead), alert: @lead.errors.full_messages.to_sentence
    end
  end

  def schedule_activity
    check_permission!(:manage, :comercial)

    case params[:activity_kind].to_s
    when "return"
      schedule_return_activity
    when "visit"
      schedule_visit_activity
    else
      respond_to do |format|
        format.html { redirect_to admin_lead_path(@lead), alert: "Selecione o tipo de atividade." }
        format.turbo_stream { render_lead_operational_turbo_stream(@lead, alert: "Selecione o tipo de atividade.", status: :unprocessable_entity) }
      end
    end
  end

  def destroy
    # Antes daqui só passavam :view + escopo do registro — ou seja, quem
    # enxergasse o lead podia apagá-lo. Excluir agora exige a permissão própria.
    unless can_destroy_lead?
      redirect_to admin_leads_path, alert: "Você não tem permissão para excluir leads."
      return
    end

    @lead.destroy
    redirect_to admin_leads_path, notice: "Lead excluído com sucesso."
  end

  private

  def lead_share_expires_at(setting)
    days = params[:expires_in_days].to_i
    days = setting.ai_property_search_share_expiration_days if days <= 0
    days = days.clamp(1, 365)
    days.days.from_now
  end

  def archive_reason_allowed?(reason)
    allowed_ids = Array(@lead.lead_pipeline_stage&.policy&.allowed_archive_reason_ids)
    return true if allowed_ids.blank?

    reason.present? && allowed_ids.include?(reason.id)
  end

  def archive_reason_options_for(lead)
    scope = current_tenant.attribute_options.for_context("lead").for_category("archive_reason").ordered
    allowed_ids = Array(lead&.lead_pipeline_stage&.policy&.allowed_archive_reason_ids)
    return scope if allowed_ids.blank?

    scope.where(id: allowed_ids)
  end

  def future_activity_allowed?(value)
    limit_days = @lead.lead_pipeline_stage&.policy&.future_activity_limit_days
    return true if limit_days.blank? || value.blank?

    due_at = parse_future_activity_time(value)
    return true if due_at.blank?

    due_at <= limit_days.days.from_now.end_of_day
  end

  def future_activity_limit_message
    limit_days = @lead.lead_pipeline_stage&.policy&.future_activity_limit_days
    return "A data informada não está disponível para a etapa atual." if limit_days.blank?

    "Esta etapa permite agendar no máximo #{limit_days} dia(s) no futuro."
  end

  def parse_future_activity_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def lead_property_share_message(habitations, url, setting)
    lead_name = @lead.display_name.presence || "Olá"
    intro = setting.ai_property_search_message(:ai_property_search_share_message, count: habitations.size)
    property_lines = habitations.map { |habitation| "- #{[habitation.codigo, habitation.display_title.presence].compact_blank.join(" · ")}" }

    [
      "#{lead_name}, #{intro}",
      property_lines.join("\n"),
      url
    ].compact_blank.join("\n\n")
  end

  def lead_share_whatsapp_url(message)
    number = Phones::Normalizer.call(@lead.display_phone)
    return "https://wa.me/?text=#{ERB::Util.url_encode(message)}" if number.blank?

    "https://wa.me/#{number}?text=#{ERB::Util.url_encode(message)}"
  end

  def ensure_shared_property_interests!(habitations)
    habitations.each do |habitation|
      @lead.property_interests.find_or_create_by!(tenant: current_tenant, habitation:)
    end
  end

  def property_suggestion_payload(match)
    habitation = match.habitation
    {
      id: habitation.id,
      codigo: habitation.codigo,
      title: habitation.display_title,
      score: match.score,
      reasons: match.reasons
    }
  end

  def public_share_collection_url(collection)
    base = public_tenant_base_url(collection.tenant)
    "#{base}#{ai_property_share_collection_path(collection.token)}"
  end

  def public_tenant_base_url(tenant)
    tenant.public_base_url(fallback_base_url: request.base_url)
  end

  def render_property_interest_chips(share: false)
    render_to_string(
      partial: "admin/whatsapp_inbox/thread_property_interest_chips",
      formats: [:html],
      locals: {
        lead: @lead,
        show_empty: false,
        share_url: (share_properties_admin_lead_path(@lead) if share),
        shared_property_ids: @lead.shared_property_ids,
        shared_property_statuses: @lead.shared_property_statuses
      }
    )
  end

  def assign_lead_filter_state
    @q = params[:q]
    @status = params[:status]
    @status_filters = Array(params[:status]).map(&:to_s).reject(&:blank?)
    @pipeline_id = @selected_pipeline&.id
    @lead_pipeline_stage_id = params[:lead_pipeline_stage_id].to_s
    @origin = params[:origin]
    @attribution_channel = params[:attribution_channel]
    @tags = Array(params[:tags]).map(&:to_s).reject(&:blank?)
    @only_mine = params[:only_mine].to_s == "1"
    @broker_id = @only_mine ? current_admin_user&.id.to_s : params[:broker_id]
    @property_filter = params[:property_filter]
    @property_q = params[:property_q].to_s.strip
    @contact_filter = params[:contact_filter]
    @attention_filter = params[:attention_filter]
    @business_filters = Array(params[:business_filter]).map(&:to_s).reject(&:blank?)
    @activity_filters = Array(params[:activity_filter]).map(&:to_s).reject(&:blank?)
    @channel_filters = Array(params[:channel_filter]).map(&:to_s).reject(&:blank?)
    @bot_attended = params[:bot_attended].to_s == "1"
    @price_min = params[:price_min].to_s.strip
    @price_max = params[:price_max].to_s.strip
    @start_date = params[:start_date]
    @end_date = params[:end_date]
    @closed_start_date = params[:closed_start_date]
    @closed_end_date = params[:closed_end_date]
    @archive_reason_id = params[:archive_reason_id].to_s
    @include_captacoes = params[:include_captacoes].to_s == "1"
    @parsed_start_date = nil
    @parsed_end_date = nil
    @parsed_closed_start_date = nil
    @parsed_closed_end_date = nil
    @lead_filter_habitation_joined = false
  end

  def filtered_lead_scope_for_current_user
    scope = lead_scope_for_current_user

    scope = apply_lead_search_filter(scope)

    scope = scope.where(leads: { lead_pipeline_id: @selected_pipeline.id }) if @selected_pipeline.present?
    scope = apply_status_filter(scope)
    scope = apply_pipeline_stage_filter(scope)
    scope = scope.by_origin(@origin)
    scope = apply_attribution_channel_filter(scope)
    scope = scope.with_any_tags(@tags)
    scope = apply_broker_filter(scope)
    scope = apply_property_filter(scope)
    scope = apply_contact_filter(scope)
    scope = apply_attention_filter(scope)
    scope = apply_business_filter(scope)
    scope = apply_activity_filter(scope)
    scope = apply_channel_filter(scope)
    scope = apply_bot_filter(scope)
    scope = apply_price_filter(scope)
    scope = apply_archive_reason_filter(scope)
    scope = apply_closed_at_filter(scope)
    apply_created_at_filter(scope)
  end

  def apply_lead_search_filter(scope)
    terms = lead_search_terms(@q)
    return scope if terms.blank?

    query = terms.each_with_index.map do |_term, index|
      LEAD_SEARCH_COLUMNS.map { |column| "leads.#{column} ILIKE :q#{index}" }.join(" OR ")
    end.map { |clause| "(#{clause})" }.join(" OR ")
    bind_values = terms.each_with_index.to_h do |term, index|
      [:"q#{index}", "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"]
    end

    scope.where(query, bind_values)
  end

  def lead_search_terms(value)
    query = value.to_s.strip
    return [] if query.blank?

    terms = [query]
    compact_query = query.gsub(/[[:space:][:punct:]]+/, "")
    terms << compact_query if compact_query.length >= 2 && compact_query != query
    terms << compact_query[1..] if compact_query.length >= 4 && compact_query.match?(/\A[[:alpha:]]+\z/)
    terms.compact_blank.uniq
  end

  def apply_status_filter(scope)
    return scope if @status_filters.blank?

    values = @status_filters.flat_map { |status| status_filter_values_for(status) }.compact_blank.uniq
    values.present? ? scope.where(leads: { status: values }) : scope
  end

  def hide_discarded_from_list_scope(scope)
    return scope if @status_filters.present? || @archive_reason_id.present?

    scope.where.not(leads: { status: Lead.status_value(:descartado, tenant: current_tenant) })
  end

  def kanban_status_tone
    @kanban_status_tone ||= lambda do |status|
      {
        "success" => :green,
        "danger" => :red,
        "warning" => :amber,
        "info" => :blue,
        "primary" => :blue,
        "secondary" => :gray,
        "light" => :gray,
        "dark" => :gray
      }[Lead.status_badge_class(status)] || :gray
    end
  end

  def apply_broker_filter(scope)
    return scope if @broker_id.blank?
    return scope.where(leads: { admin_user_id: nil }) if @broker_id == "unassigned"
    return scope.none unless permitted_admin_user_ids_for_leads.include?(@broker_id.to_i)

    scope.where(leads: { admin_user_id: @broker_id })
  end

  def apply_pipeline_stage_filter(scope)
    return scope if @lead_pipeline_stage_id.blank?

    stage_id = @lead_pipeline_stage_id.to_i
    visible_stage_ids = visible_stages_for(current_tenant.lead_pipeline_stages.active.where(id: stage_id)).map(&:id)
    return scope.none unless visible_stage_ids.include?(stage_id)

    scope.where(leads: { lead_pipeline_stage_id: stage_id })
  end

  def apply_property_filter(scope)
    case @property_filter
    when "with_property"
      scope = scope.where.not(leads: { property_id: nil })
    when "general"
      scope = scope.where(leads: { property_id: nil })
    when "unavailable_property"
      scope = scope.where.not(leads: { property_id: nil }).where.not(leads: { property_id: current_tenant.habitations.select(:id) })
    end

    return scope if @property_q.blank?

    term = "%#{ActiveRecord::Base.sanitize_sql_like(@property_q)}%"
    property_ids = current_tenant.habitations
                   .where("codigo ILIKE :q OR titulo_anuncio ILIKE :q OR nome_empreendimento ILIKE :q", q: term)
                   .select(:id)
    scope.where(leads: { property_id: property_ids })
  end

  def apply_contact_filter(scope)
    case @contact_filter
    when "with_phone"
      scope.where(phone_presence_sql)
    when "with_email"
      scope.where(email_presence_sql)
    when "missing_contact"
      scope.where("NOT (#{phone_presence_sql})").where("NOT (#{email_presence_sql})")
    else
      scope
    end
  end

  def apply_attribution_channel_filter(scope)
    case @attribution_channel.to_s
    when ""
      scope
    when "direct"
      scope.where(attribution_channel: [nil, "", "direct"])
    else
      scope.where(attribution_channel: @attribution_channel)
    end
  end

  def apply_business_filter(scope)
    return scope if @business_filters.blank?

    values = @business_filters & (BUSINESS_FILTERS.keys + ["undefined"])
    return scope if values.blank?

    scope = with_filter_habitation_join(scope)
    clauses = values.filter_map do |value|
      case value
      when "sale"
        "(COALESCE(habitations.valor_venda_cents, 0) > 0 OR #{BUSINESS_FILTERS.fetch(value)})"
      when "rental"
        "(COALESCE(habitations.valor_locacao_cents, 0) > 0 OR #{BUSINESS_FILTERS.fetch(value)})"
      when "undefined"
        known = BUSINESS_FILTERS.values.join(" OR ")
        "(COALESCE(habitations.valor_venda_cents, 0) <= 0 AND COALESCE(habitations.valor_locacao_cents, 0) <= 0 AND NOT (#{known}))"
      else
        BUSINESS_FILTERS[value]
      end
    end

    clauses.present? ? scope.where(clauses.join(" OR ")) : scope
  end

  def apply_activity_filter(scope)
    return scope if @activity_filters.blank?

    values = @activity_filters & %w[first_contact schedule_activity return_customer scheduled_visit qualification_divergence]
    return scope if values.blank?

    clauses = values.filter_map do |value|
      case value
      when "first_contact"
        "leads.id NOT IN (#{LeadActivity.contact_attempts.select(:lead_id).to_sql})"
      when "schedule_activity"
        "leads.id IN (#{Task.where(tenant_id: current_tenant.id).pendentes.select(:lead_id).to_sql}) OR leads.id IN (#{pwa_external_schedule_scope(scope, visits: false).select(:lead_id).to_sql})"
      when "return_customer"
        returning_tasks = Task.where(tenant_id: current_tenant.id).pendentes.where("LOWER(tasks.title) LIKE '%retornar%'").select(:lead_id)
        returning_external = pwa_external_schedule_scope(scope, visits: false).where("#{EXTERNAL_SCHEDULE_TEXT_SQL} LIKE '%retornar%' OR #{EXTERNAL_SCHEDULE_TEXT_SQL} LIKE '%feedback_customer%'").select(:lead_id)
        "leads.id IN (#{returning_tasks.to_sql}) OR leads.id IN (#{returning_external.to_sql})"
      when "scheduled_visit"
        appointments = Appointment.where(tenant_id: current_tenant.id, kind: "visita", status: "agendado").select(:lead_id)
        "leads.id IN (#{appointments.to_sql}) OR leads.id IN (#{pwa_external_schedule_scope(scope, visits: true).select(:lead_id).to_sql})"
      when "qualification_divergence"
        divergence_stage_ids = LeadPipelineStagePolicy
          .where(tenant_id: current_tenant.id, divergence_queue_enabled: true)
          .select(:lead_pipeline_stage_id)
        "leads.lead_pipeline_stage_id IN (#{divergence_stage_ids.to_sql}) " \
          "AND NULLIF(leads.broker_qualification_status, '') IS NOT NULL " \
          "AND NULLIF(leads.manager_qualification_status, '') IS NOT NULL " \
          "AND leads.broker_qualification_status <> leads.manager_qualification_status"
      end
    end

    clauses.present? ? scope.where(clauses.map { |clause| "(#{clause})" }.join(" OR ")) : scope
  end

  def apply_channel_filter(scope)
    return scope if @channel_filters.blank?

    clauses = (@channel_filters & CHANNEL_FILTERS.keys).map { |value| CHANNEL_FILTERS.fetch(value) }
    clauses.present? ? scope.where(clauses.join(" OR ")) : scope
  end

  def apply_bot_filter(scope)
    return scope unless @bot_attended

    scope.where(
      "leads.id IN (:activity_leads) OR #{LEAD_FILTER_TEXT_SQL} LIKE '%bot%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%robô%' OR #{LEAD_FILTER_TEXT_SQL} LIKE '%robo%'",
      activity_leads: LeadActivity.where(kind: %w[automation automation_event]).select(:lead_id)
    )
  end

  def apply_price_filter(scope)
    min = parse_decimal_filter(@price_min)
    max = parse_decimal_filter(@price_max)
    return scope if min.blank? && max.blank?

    scope = with_filter_habitation_join(scope)
    scope = scope.where("#{LEAD_PRICE_SQL} >= :min", min: min) if min.present?
    scope = scope.where("#{LEAD_PRICE_SQL} <= :max", max: max) if max.present?
    scope
  end

  def apply_archive_reason_filter(scope)
    return scope if @archive_reason_id.blank?

    reason_id = @archive_reason_id.to_i
    reason_exists = current_tenant.attribute_options
                                  .for_context("lead")
                                  .for_category("archive_reason")
                                  .where(id: reason_id)
                                  .exists?
    return scope.none unless reason_exists

    scope.where(leads: { archive_reason_id: reason_id })
  end

  def apply_attention_filter(scope)
    case @attention_filter.to_s
    when "requires_action"
      scope.where(status: active_lead_status_values_with_blank).where(attention_leads_sql)
    when "task_overdue"
      scope.where(status: active_lead_status_values_with_blank).where(id: operational_task_scope.atrasadas.select(:lead_id))
    when "task_due_today"
      scope.where(status: active_lead_status_values_with_blank).where(id: operational_task_scope.hoje.select(:lead_id))
    when "stalled"
      scope.where(status: active_lead_status_values_with_blank).where("leads.updated_at < ?", 2.days.ago)
    when "unassigned"
      scope.where(admin_user_id: nil, status: active_lead_status_values_with_blank)
    when "holding"
      scope.holding
    when "no_first_contact"
      scope.where(status: active_lead_status_values_with_blank)
        .where.not(id: LeadActivity.contact_attempts.select(:lead_id))
    when "sla_overdue"
      scope.where(status: active_lead_status_values_with_blank)
        .where("leads.created_at < ?", first_contact_sla_hours.hours.ago)
        .where.not(id: LeadActivity.contact_attempts.select(:lead_id))
    when "with_opportunity"
      scope.where(
        "leads.status IN (:closed) OR leads.id IN (:appointment_ids) OR leads.id IN (:proposal_ids)",
        closed: closed_lead_status_values,
        appointment_ids: Appointment.where(kind: "visita").select(:lead_id),
        proposal_ids: Proposal.where.not(status: "rascunho").select(:lead_id)
      )
    when "unsuccessful_attempts"
      scope.where(id: LeadActivity.unsuccessful_contact_attempts.select(:lead_id))
    when "eligible_redistribution"
      scope.where(id: eligible_automation_lead_ids(action_type: "redistribute_lead"))
    when "second_attempt"
      scope.joins(:lead_pipeline_stage).where("lead_pipeline_stages.name ILIKE ?", "%segunda%")
    when "archived_unsuccessful"
      reason_ids = current_tenant.attribute_options
                                 .for_context("lead")
                                 .for_category("archive_reason")
                                 .where("name ILIKE ? OR name ILIKE ?", "%não respondeu%", "%contatar%")
                                 .select(:id)
      scope.where(archive_reason_id: reason_ids)
    else
      scope
    end
  end

  def eligible_automation_lead_ids(action_type:)
    stage_ids = current_tenant.lead_pipeline_stage_automations
                              .active
                              .where(action_type: action_type)
                              .where("COALESCE((action_config ->> 'unsuccessful_attempt_limit')::integer, 0) > 0")
                              .select(:lead_pipeline_stage_id)
    current_tenant.leads.where(lead_pipeline_stage_id: stage_ids)
                  .joins(:activities)
                  .merge(LeadActivity.unsuccessful_contact_attempts)
                  .group("leads.id")
                  .having("COUNT(lead_activities.id) >= COALESCE((SELECT MIN((lpsa.action_config ->> 'unsuccessful_attempt_limit')::integer) FROM lead_pipeline_stage_automations lpsa WHERE lpsa.lead_pipeline_stage_id = leads.lead_pipeline_stage_id AND lpsa.active = TRUE AND lpsa.action_type = ? AND COALESCE((lpsa.action_config ->> 'unsuccessful_attempt_limit')::integer, 0) > 0), 999999)", action_type)
                  .select(:id)
  end

  def commercial_report_csv(scope, include_captacoes:)
    leads = scope.reorder(nil).includes(:admin_user).to_a
    property_ids = leads.map(&:property_id).compact.uniq
    properties_by_id = current_tenant.habitations.where(id: property_ids).index_by(&:id)

    CSV.generate(headers: false, col_sep: ";") do |csv|
      csv << [commercial_report_title(scope)]
      csv << []

      leads.sort_by { |lead| [commercial_report_user_label(lead), lead.created_at || Time.zone.at(0), lead.id] }
           .group_by { |lead| commercial_report_user_label(lead) }
           .each do |user_label, user_leads|
        csv << ["USUÁRIO: #{user_label}", nil, nil, nil, nil, nil, "Total de leads", user_leads.size]
        csv << commercial_report_headers

        user_leads.each do |lead|
          property = properties_by_id[lead.property_id]
          last_attempt = lead.activities.unsuccessful_contact_attempts.recent.first
          csv << [
            "Lead",
            report_datetime(lead.created_at),
            lead.display_name,
            lead.display_phone,
            lead.display_email,
            commercial_report_source_label(lead),
            lead.admin_user&.name || "Sem corretor",
            lead.lead_pipeline_stage&.name || lead.status,
            lead_unsuccessful_attempt_count(lead),
            report_datetime(last_attempt&.created_at),
            commercial_report_archive_reason(lead),
            property&.display_title || lead.product,
            report_property_city(property, lead:)
          ]
        end
        csv << []
      end

      append_captacoes_to_report(csv) if include_captacoes
    end
  end

  def commercial_report_xlsx(scope, include_captacoes:)
    leads = scope.reorder(nil).includes(:admin_user, :distribution_rule).to_a
    property_ids = leads.map(&:property_id).compact.uniq
    properties_by_id = current_tenant.habitations.where(id: property_ids).index_by(&:id)
    rows = commercial_report_xlsx_rows(scope, leads, properties_by_id)

    if include_captacoes
      rows << commercial_report_xlsx_blank_row
      rows << commercial_report_xlsx_blank_row
      rows << commercial_report_xlsx_section_title("CAPTAÇÕES")
      rows << commercial_report_xlsx_header_row
      captacao_report_scope.reorder(:id).find_each(batch_size: 500) do |captacao|
        rows << {
          style: :body,
          cells: [
            captacao.proprietario.presence || captacao.proprietor&.name,
            captacao.proprietario_email.presence || captacao.proprietor&.email,
            captacao.proprietario_celular.presence || captacao.proprietor&.phone_primary,
            "Captação",
            captacao.admin_user&.name || captacao.corretor_nome || "Sem corretor",
            "Não",
            captacao.display_title
          ]
        }
      end
    end

    build_xlsx_package(
      "[Content_Types].xml" => xlsx_content_types_xml,
      "_rels/.rels" => xlsx_root_relationships_xml,
      "docProps/app.xml" => xlsx_app_properties_xml,
      "docProps/core.xml" => xlsx_core_properties_xml,
      "xl/workbook.xml" => xlsx_workbook_xml,
      "xl/_rels/workbook.xml.rels" => xlsx_workbook_relationships_xml,
      "xl/styles.xml" => xlsx_styles_xml,
      "xl/worksheets/sheet1.xml" => xlsx_sheet_xml(rows)
    )
  end

  def commercial_report_xlsx_rows(scope, leads, properties_by_id)
    rows = [
      commercial_report_xlsx_blank_row,
      { style: :title, height: 30, cells: [commercial_report_title(scope), nil, nil, nil, nil, nil, nil] },
      { style: :title, height: 30, cells: Array.new(REPORT_XLSX_HEADERS.size) },
      commercial_report_xlsx_blank_row
    ]

    grouped_leads = leads
      .sort_by { |lead| [commercial_report_user_label(lead), lead.created_at || Time.zone.at(0), lead.id] }
      .group_by { |lead| commercial_report_user_label(lead) }

    grouped_leads.each_value do |user_leads|
      rows << commercial_report_xlsx_header_row
      user_leads.each do |lead|
        property = properties_by_id[lead.property_id]
        rows << { style: :body, cells: commercial_report_xlsx_lead_row(lead, property) }
      end
      rows << commercial_report_xlsx_blank_row
      rows << commercial_report_xlsx_blank_row
    end

    rows
  end

  def commercial_report_xlsx_header_row
    { style: :header, height: 57.6, cells: REPORT_XLSX_HEADERS }
  end

  def commercial_report_xlsx_section_title(title)
    { style: :header, height: 28.8, cells: [title, nil, nil, nil, nil, nil, nil] }
  end

  def commercial_report_xlsx_blank_row
    { style: :default, cells: Array.new(REPORT_XLSX_HEADERS.size) }
  end

  def commercial_report_xlsx_lead_row(lead, property)
    [
      lead.display_name,
      lead.display_email,
      lead.display_phone,
      commercial_report_source_label(lead),
      lead.admin_user&.name || "Sem corretor",
      commercial_report_pool_attendance_label(lead),
      property&.display_title || lead.product
    ]
  end

  def commercial_report_pool_attendance_label(lead)
    values = [
      lead.attribution_data.is_a?(Hash) ? lead.attribution_data["from_hierarchy_company"] : nil,
      lead.other_information.is_a?(Hash) ? lead.other_information.dig("attributes", "from_hierarchy_company") : nil,
      lead.other_information.is_a?(Hash) ? lead.other_information.dig("external_lead_payload", "attributes", "from_hierarchy_company") : nil,
      lead.distribution_rule&.shark_tank?,
      Lead.status_value(lead.status) == Lead.status_value(:waiting_acceptance)
    ]

    ActiveModel::Type::Boolean.new.cast(values.find { |value| !value.nil? }) ? "Sim" : "Não"
  end

  def xlsx_sheet_xml(rows)
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <dimension ref="A1:G#{rows.size}"/>
        <sheetViews><sheetView workbookViewId="0"/></sheetViews>
        <sheetFormatPr defaultRowHeight="15"/>
        <cols>
          #{REPORT_XLSX_COLUMN_WIDTHS.each_with_index.map { |width, index| %(<col min="#{index + 1}" max="#{index + 1}" width="#{width}" customWidth="1"/>) }.join}
        </cols>
        <sheetData>
          #{rows.each_with_index.map { |row, index| xlsx_row_xml(index + 1, row) }.join}
        </sheetData>
        <mergeCells count="1"><mergeCell ref="A2:G3"/></mergeCells>
        <pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>
      </worksheet>
    XML
  end

  def xlsx_row_xml(row_index, row)
    style_id = xlsx_style_id(row[:style])
    height = row[:height].present? ? %( ht="#{row[:height]}" customHeight="1") : ""
    cells = row.fetch(:cells).each_with_index.map do |value, column_index|
      xlsx_cell_xml(row_index, column_index + 1, value, style_id)
    end.join

    %(<row r="#{row_index}"#{height}>#{cells}</row>)
  end

  def xlsx_cell_xml(row_index, column_index, value, style_id)
    reference = "#{xlsx_column_name(column_index)}#{row_index}"
    return %(<c r="#{reference}" s="#{style_id}"/>) if value.blank?

    %(<c r="#{reference}" s="#{style_id}" t="inlineStr"><is><t>#{CGI.escapeHTML(value.to_s)}</t></is></c>)
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

  def xlsx_style_id(style)
    { default: 0, title: 1, header: 2, body: 3 }.fetch(style || :default)
  end

  def xlsx_content_types_xml
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

  def xlsx_root_relationships_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
        <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
      </Relationships>
    XML
  end

  def xlsx_workbook_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="Relatório" sheetId="1" r:id="rId1"/></sheets>
      </workbook>
    XML
  end

  def xlsx_workbook_relationships_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
      </Relationships>
    XML
  end

  def xlsx_app_properties_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">
        <Application>Unitymob</Application>
      </Properties>
    XML
  end

  def xlsx_core_properties_xml
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

  def xlsx_styles_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <fonts count="3">
          <font><sz val="11"/><name val="Arial"/></font>
          <font><b/><sz val="16"/><name val="Arial"/></font>
          <font><b/><sz val="11"/><name val="Arial"/></font>
        </fonts>
        <fills count="3">
          <fill><patternFill patternType="none"/></fill>
          <fill><patternFill patternType="gray125"/></fill>
          <fill><patternFill patternType="solid"><fgColor rgb="FFF5F5F6"/><bgColor indexed="64"/></patternFill></fill>
        </fills>
        <borders count="3">
          <border><left/><right/><top/><bottom/><diagonal/></border>
          <border><left style="medium"/><right style="medium"/><top style="medium"/><bottom style="medium"/><diagonal/></border>
          <border><left style="thin"/><right style="thin"/><top style="thin"/><bottom style="thin"/><diagonal/></border>
        </borders>
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="4">
          <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
          <xf numFmtId="0" fontId="1" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>
          <xf numFmtId="0" fontId="2" fillId="2" borderId="2" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="bottom" wrapText="1"/></xf>
          <xf numFmtId="0" fontId="0" fillId="0" borderId="2" xfId="0" applyBorder="1"/>
        </cellXfs>
        <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
        <dxfs count="0"/>
        <tableStyles count="0" defaultTableStyle="TableStyleMedium2" defaultPivotStyle="PivotStyleLight16"/>
      </styleSheet>
    XML
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

  def commercial_report_headers
    [
      "Tipo",
      "Data de entrada",
      "Cliente",
      "Telefone",
      "E-mail",
      "Canal/Fonte",
      "Corretor atual",
      "Etapa",
      "Tentativas sem resposta",
      "Última tentativa",
      "Motivo de arquivamento",
      "Imóvel/Captação",
      "Cidade"
    ]
  end

  def commercial_report_title(scope)
    start_date = parsed_start_date || scope.reorder(nil).minimum(:created_at)&.to_date
    end_date = parsed_end_date || scope.reorder(nil).maximum(:created_at)&.to_date
    return "RELATÓRIO LEADS" if start_date.blank? && end_date.blank?

    dates = [start_date, end_date].compact.map { |date| I18n.l(date, format: "%d/%m/%Y") }
    "RELATÓRIO LEADS #{dates.join(" A ")}"
  end

  def commercial_report_user_label(lead)
    lead.admin_user&.name.presence || "Sem corretor"
  end

  def append_captacoes_to_report(csv)
    csv << []
    csv << ["CAPTAÇÕES"]
    csv << commercial_report_headers
    captacao_report_scope.reorder(:id).find_each(batch_size: 500) do |captacao|
      csv << commercial_report_captacao_row(captacao)
    end
  end

  def commercial_report_captacao_row(captacao)
    [
      "Captação",
      report_datetime(captacao.created_at),
      captacao.proprietario.presence || captacao.proprietor&.name,
      captacao.proprietario_celular.presence || captacao.proprietor&.phone_primary,
      captacao.proprietario_email.presence || captacao.proprietor&.email,
      "Captação",
      captacao.admin_user&.name || captacao.corretor_nome || "Sem corretor",
      captacao.intake_status_label,
      nil,
      nil,
      nil,
      captacao.display_title,
      captacao.cidade
    ]
  end

  def captacao_report_scope
    scope = current_tenant.habitations.broker_intakes.includes(:admin_user, :address, :proprietor).order(created_at: :asc)
    scope = scope.where("habitations.created_at >= ?", parsed_start_date.beginning_of_day) if parsed_start_date.present?
    scope = scope.where("habitations.created_at <= ?", parsed_end_date.end_of_day) if parsed_end_date.present?
    if @broker_id.present? && @broker_id != "unassigned" && permitted_admin_user_ids_for_leads.include?(@broker_id.to_i)
      scope = scope.where(admin_user_id: @broker_id)
    end
    scope
  end

  def report_datetime(value)
    value.present? ? I18n.l(value.in_time_zone, format: "%d/%m/%Y %H:%M") : nil
  end

  def commercial_report_source_label(lead)
    summary = helpers.lead_conversion_summary(lead)
    [summary[:origin], summary[:channel_label]].compact_blank.uniq.join(" / ").presence ||
      [lead.origin, lead.attribution_channel].compact_blank.uniq.join(" / ")
  end

  def commercial_report_archive_reason(lead)
    native_reason = lead.archive_reason&.name.presence || lead.archive_note.presence
    return native_reason if native_reason.present?

    external_reason = external_archive_reason_for(lead)
    return external_reason if external_reason.present?

    external_lead_without_archive_reason?(lead) ? "Sem motivo migrado" : nil
  end

  def external_archive_reason_for(lead)
    info = lead.other_information.is_a?(Hash) ? lead.other_information : {}
    attribution = lead.attribution_data.is_a?(Hash) ? lead.attribution_data : {}
    attrs = info.dig("external_lead_payload", "attributes").is_a?(Hash) ? info.dig("external_lead_payload", "attributes") : {}
    legacy_attrs = info["attributes"].is_a?(Hash) ? info["attributes"] : {}
    c2s_attrs = info.dig("c2s_payload", "attributes").is_a?(Hash) ? info.dig("c2s_payload", "attributes") : {}

    candidates = [
      attribution.dig("lost_reasons", "name"),
      attribution.dig("lost_reasons", "reason"),
      attribution.dig("archive_details", "archive_reason"),
      attribution.dig("archive_details", "reason"),
      attribution.dig("archive_details", "archive_notes"),
      attrs.dig("lost_reasons", "name"),
      attrs.dig("lost_reasons", "reason"),
      attrs.dig("archive_details", "archive_reason"),
      attrs.dig("archive_details", "reason"),
      attrs.dig("archive_details", "archive_notes"),
      legacy_attrs.dig("lost_reasons", "name"),
      legacy_attrs.dig("lost_reasons", "reason"),
      legacy_attrs.dig("archive_details", "archive_reason"),
      legacy_attrs.dig("archive_details", "reason"),
      legacy_attrs.dig("archive_details", "archive_notes"),
      c2s_attrs.dig("lost_reasons", "name"),
      c2s_attrs.dig("lost_reasons", "reason"),
      c2s_attrs.dig("archive_details", "archive_reason"),
      c2s_attrs.dig("archive_details", "reason"),
      c2s_attrs.dig("archive_details", "archive_notes")
    ]

    candidates.flat_map { |value| archive_reason_values(value) }.find(&:present?)
  end

  def archive_reason_values(value)
    case value
    when Array
      value.flat_map { |item| archive_reason_values(item) }
    when Hash
      %w[name reason title label description archive_reason archive_notes].filter_map { |key| normalize_external_archive_reason(value[key]) }
    else
      [normalize_external_archive_reason(value)]
    end
  end

  def normalize_external_archive_reason(value)
    text = value.to_s.squish
    return if text.blank?

    {
      "inactive" => "Inativo",
      "not_answered" => "Cliente não respondeu",
      "no_answer" => "Cliente não respondeu",
      "without_success" => "Sem sucesso de atendimento",
      "lost" => "Perdido",
      "archived" => "Arquivado"
    }[text.parameterize(separator: "_")] || text
  end

  def external_lead_without_archive_reason?(lead)
    return false unless lead.status.to_s.match?(/descart|arquiv|perdid/i)

    info = lead.other_information.is_a?(Hash) ? lead.other_information : {}
    attribution = lead.attribution_data.is_a?(Hash) ? lead.attribution_data : {}
    info["source"].to_s.in?(%w[c2s external_lead_migration]) ||
      attribution["provider"].to_s == ExternalLeadMigration::LeadMapper::PROVIDER_KEY ||
      lead.origin.to_s.match?(/c2s|migra/i)
  end

  def report_property_city(property, lead: nil)
    property_city = property.try(:cidade).presence || property.try(:city).presence || property&.address&.city
    return property_city if property_city.present?
    return if lead.blank?

    external_product_for_report(lead)["city"].presence
  end

  def external_product_for_report(lead)
    info = lead.other_information.is_a?(Hash) ? lead.other_information : {}
    attribution = lead.attribution_data.is_a?(Hash) ? lead.attribution_data : {}
    product = attribution["product"]
    product = info["external_lead_product"] if !product.is_a?(Hash)
    product = info.dig("external_lead_payload", "attributes", "product") if !product.is_a?(Hash)
    product = info.dig("attributes", "product") if !product.is_a?(Hash)
    product = info.dig("c2s_payload", "attributes", "product") if !product.is_a?(Hash)
    product.is_a?(Hash) ? product : {}
  end

  def first_contact_sla_hours
    @first_contact_sla_hours ||= LeadSetting.instance(tenant: current_tenant).first_contact_sla_hours_value
  end

  def apply_created_at_filter(scope)
    if parsed_start_date.present?
      scope = scope.where("leads.created_at >= ?", parsed_start_date.beginning_of_day)
    end

    if parsed_end_date.present?
      scope = scope.where("leads.created_at <= ?", parsed_end_date.end_of_day)
    end

    scope
  end

  def apply_closed_at_filter(scope)
    return scope if parsed_closed_start_date.blank? && parsed_closed_end_date.blank?

    scope = scope.where(status: closed_lead_status_values)
    scope = scope.where("leads.closed_at >= ?", parsed_closed_start_date.beginning_of_day) if parsed_closed_start_date.present?
    scope = scope.where("leads.closed_at <= ?", parsed_closed_end_date.end_of_day) if parsed_closed_end_date.present?
    scope
  end

  def parsed_start_date
    @parsed_start_date ||= parse_filter_date(@start_date)
  end

  def parsed_end_date
    @parsed_end_date ||= parse_filter_date(@end_date)
  end

  def parsed_closed_start_date
    @parsed_closed_start_date ||= parse_filter_date(@closed_start_date)
  end

  def parsed_closed_end_date
    @parsed_closed_end_date ||= parse_filter_date(@closed_end_date)
  end

  def parse_decimal_filter(value)
    normalized = value.to_s.gsub(/[^\d,\.]/, "")
    return nil if normalized.blank?

    if normalized.include?(",")
      normalized = normalized.gsub(".", "").tr(",", ".")
    end

    BigDecimal(normalized)
  rescue ArgumentError
    nil
  end

  def with_filter_habitation_join(scope)
    return scope if @lead_filter_habitation_joined

    @lead_filter_habitation_joined = true
    scope.joins("LEFT JOIN habitations ON habitations.id = leads.property_id AND habitations.tenant_id = leads.tenant_id")
  end

  def active_lead_status_values
    pipeline_open_statuses = current_tenant.lead_pipeline_stages.active.where(stage_type: "open").pluck(:name)
    legacy_open_statuses = Lead::LEGACY_STATUSES - [Lead.status_value(:descartado), Lead.status_value(:concluido)]

    (pipeline_open_statuses + legacy_open_statuses).compact_blank.uniq
  end

  def pwa_priority_lead_status_values
    default_statuses = current_tenant.lead_pipelines.active.includes(:stages).filter_map { |pipeline| pipeline.default_stage&.name }

    (default_statuses + [Lead.status_value(:novo), Lead.status_value(:waiting_acceptance), Lead.status_value(:represado)]).compact_blank.uniq
  end

  def closed_lead_status_values
    pipeline_won_statuses = current_tenant.lead_pipeline_stages.active.where(stage_type: "won").pluck(:name)

    ([Lead.status_value(:concluido)] + pipeline_won_statuses).compact_blank.uniq
  end

  def active_lead_status_values_with_blank
    active_lead_status_values + [nil]
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

  def operational_task_scope
    current_tenant.tasks.operational_current
  end

  def parse_filter_date(value)
    return nil if value.blank?

    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end

  def phone_presence_sql
    "NULLIF(TRIM(COALESCE(leads.client_phone, '')), '') IS NOT NULL OR NULLIF(TRIM(COALESCE(leads.phone, '')), '') IS NOT NULL"
  end

  def email_presence_sql
    "NULLIF(TRIM(COALESCE(leads.client_email, '')), '') IS NOT NULL OR NULLIF(TRIM(COALESCE(leads.email, '')), '') IS NOT NULL"
  end

  # Modo de visualização da lista de leads (kanban/list), lembrado por usuário.
  # Com `?view=` válido na URL, usa e salva a escolha; sem param, cai na
  # preferência salva e, por fim, no padrão kanban.
  def resolve_view_mode
    requested = params[:view].presence_in(%w[kanban list])

    if requested
      if current_admin_user && current_admin_user.leads_view_mode != requested
        current_admin_user.update_column(:leads_view_mode, requested)
      end
      requested
    else
      current_admin_user&.leads_view_mode.presence_in(%w[kanban list]) || "kanban"
    end
  end

  def set_lead
    @lead = current_tenant.leads.find(params[:id])
  end

  def existing_whatsapp_conversation_for(lead)
    scope = current_tenant.whatsapp_conversations
    bsuid = lead.business_scoped_user_id.presence
    phone = normalize_whatsapp_phone(lead.display_phone) if lead.display_phone.present?

    scope.find_by(lead: lead) ||
      (scope.find_by(business_scoped_user_id: bsuid) if bsuid.present?) ||
      (scope.find_by(contact_phone: phone) if phone.present?)
  end

  def find_or_create_whatsapp_conversation_for!(lead)
    recipient = lead.whatsapp_recipient
    raise ArgumentError, "Este lead não possui telefone ou BSUID para abrir conversa no WhatsApp." if recipient.blank?

    bsuid = lead.business_scoped_user_id.presence
    phone = normalize_whatsapp_phone(lead.display_phone) if lead.display_phone.present?
    conversation = existing_whatsapp_conversation_for(lead)
    conversation = bind_whatsapp_conversation_to_lead!(conversation, lead) if conversation&.lead_id.blank?
    conversation ||= if bsuid.present?
                       current_tenant.whatsapp_conversations.find_or_initialize_by(business_scoped_user_id: bsuid)
                     else
                       current_tenant.whatsapp_conversations.find_or_initialize_by(contact_phone: phone)
                     end

    if conversation.lead_id.blank? || conversation.lead_id == lead.id
      conversation.contact_phone ||= phone if phone.present?
      conversation.business_scoped_user_id ||= bsuid if bsuid.present?
      conversation.contact_name ||= lead.display_name
      conversation.lead ||= lead
      conversation.status ||= "open"
      conversation.save!
    end
    conversation
  end

  def bind_whatsapp_conversation_to_lead!(conversation, lead)
    return conversation if conversation.blank?
    return conversation if conversation.lead_id == lead.id

    previous_lead_id = conversation.lead_id
    conversation.lead = lead
    conversation.contact_name = lead.display_name if lead.display_name.present?
    conversation.status ||= "open"
    conversation.save! if conversation.changed?
    Rails.logger.info(
      "[Admin::LeadsController#bind_whatsapp_conversation_to_lead] " \
      "tenant_id=#{current_tenant.id} conversation_id=#{conversation.id} " \
      "previous_lead_id=#{previous_lead_id} lead_id=#{lead.id}"
    )
    conversation
  end

  def normalize_whatsapp_phone(value)
    Phones::Normalizer.call(value).to_s
  end

  def schedule_return_activity
    due_at = params[:due_at].presence
    unless future_activity_allowed?(due_at)
      return respond_to do |format|
        format.html { redirect_to admin_lead_path(@lead), alert: future_activity_limit_message }
        format.turbo_stream { render_lead_operational_turbo_stream(@lead, alert: future_activity_limit_message, status: :unprocessable_entity) }
      end
    end

    task = current_tenant.tasks.create(
      lead: @lead,
      admin_user: current_admin_user,
      created_by_id: current_admin_user.id,
      title: "Retornar para o cliente",
      kind: "follow_up",
      due_at: due_at,
      description: params[:notes]
    )

    if task.persisted?
      LeadActivity.log!(lead: @lead, kind: "activity_scheduled", metadata: { activity_kind: "return", due_at: task.due_at, by: current_admin_user&.name })
      respond_to do |format|
        format.html { redirect_to admin_lead_path(@lead), notice: "Retorno agendado." }
        format.turbo_stream { render_lead_operational_turbo_stream(@lead, notice: "Retorno agendado.") }
      end
    else
      respond_to do |format|
        format.html { redirect_to admin_lead_path(@lead), alert: task.errors.full_messages.to_sentence }
        format.turbo_stream { render_lead_operational_turbo_stream(@lead, alert: task.errors.full_messages.to_sentence, status: :unprocessable_entity) }
      end
    end
  end

  def schedule_visit_activity
    starts_at = params[:starts_at].presence
    unless future_activity_allowed?(starts_at)
      return respond_to do |format|
        format.html { redirect_to admin_lead_path(@lead), alert: future_activity_limit_message }
        format.turbo_stream { render_lead_operational_turbo_stream(@lead, alert: future_activity_limit_message, status: :unprocessable_entity) }
      end
    end

    appointment = current_tenant.appointments.new(
      lead: @lead,
      admin_user: current_admin_user,
      habitation_id: @lead.property_id,
      title: "Visita — #{@lead.display_name}",
      kind: "visita",
      starts_at: starts_at,
      ends_at: params[:ends_at].presence,
      location: params[:location],
      notes: params[:notes],
      properties_to_visit_count: params[:properties_to_visit_count].presence,
      invite_via_email: params[:invite_via_email].present?,
      invite_via_whatsapp: params[:invite_via_whatsapp].present?,
      invite_email_recipients: params[:invite_email_recipients]
    )

    unless appointment.save
      return respond_to do |format|
        format.html { redirect_to admin_lead_path(@lead), alert: appointment.errors.full_messages.to_sentence }
        format.turbo_stream { render_lead_operational_turbo_stream(@lead, alert: appointment.errors.full_messages.to_sentence, status: :unprocessable_entity) }
      end
    end

    send_visit_invites(appointment)
    LeadActivity.log!(lead: @lead, kind: "activity_scheduled", metadata: { activity_kind: "visit", starts_at: appointment.starts_at, by: current_admin_user&.name })
    respond_to do |format|
      format.html { redirect_to admin_lead_path(@lead), notice: "Visita agendada." }
      format.turbo_stream { render_lead_operational_turbo_stream(@lead, notice: "Visita agendada.") }
    end
  end

  def send_visit_invites(appointment)
    if appointment.invite_via_email?
      recipients = appointment.invite_email_recipients.to_s.split(/[,;\s]+/).map(&:strip).select { |email| email.match?(URI::MailTo::EMAIL_REGEXP) }
      AppointmentMailer.with(appointment: appointment, recipients: recipients, tenant: appointment.tenant).invite.deliver_later if recipients.present?
    end

    return unless appointment.invite_via_whatsapp?

    begin
      conversation = find_or_create_whatsapp_conversation_for!(@lead)
      body = "Visita agendada para #{l(appointment.starts_at, format: "%d/%m/%Y às %H:%M")}" \
             "#{appointment.location.present? ? " em #{appointment.location}" : ""}."
      message = conversation.messages.create!(direction: "outbound", status: "pending", msg_type: "text", body: body, admin_user: current_admin_user)
      conversation.touch_last_message!(message)
      Whatsapp::SendMessageJob.dispatch(message.id, tenant_id: message.tenant_id)
    rescue ArgumentError => e
      Rails.logger.warn("[Admin::LeadsController#send_visit_invites] convite WhatsApp não enviado: #{e.message}")
    end
  end

  def load_lead_whatsapp_context
    @lead_whatsapp_panel_enabled = LeadSetting.instance(tenant: current_tenant).lead_whatsapp_conversation_enabled?
    return apply_lead_whatsapp_disabled! unless @lead_whatsapp_panel_enabled

    integration = WhatsappBusinessIntegration.current(current_tenant)

    @lead_activation_template = Whatsapp::LeadActivationTemplate.for(tenant: current_tenant, integration: integration)
    @whatsapp_templates = approved_lead_whatsapp_templates(integration)
    @whatsapp_conversation =
      if auto_open_lead_whatsapp_conversation?(integration)
        find_or_create_whatsapp_conversation_for!(@lead)
      else
        current_tenant.whatsapp_conversations.find_by(lead: @lead)
      end
    # 100 e nao 12: com 12 o historico (videos/audios de dias atras) sumia do painel
    @whatsapp_messages = if @whatsapp_conversation && @whatsapp_conversation.lead_id == @lead.id
                            lead_whatsapp_panel_messages(@whatsapp_conversation)
                          else
                            []
                          end
    snapshot = @whatsapp_conversation ? Whatsapp::ThreadContextSnapshot.new(
      conversation: @whatsapp_conversation,
      messages: @whatsapp_messages,
      focus_mode: false,
      tenant: current_tenant
    ) : nil
    @whatsapp_summary = snapshot ? snapshot.to_h.fetch(:thread_summary) : { pending_count: 0, failed_count: 0, media_count: 0, last_activity_at: nil }
    @whatsapp_thread_context_locals = snapshot ? lead_whatsapp_thread_context(snapshot) : {}
  rescue => e
    Rails.logger.warn("[Admin::LeadsController#load_lead_whatsapp_context] lead_id=#{@lead&.id} tenant_id=#{current_tenant&.id} erro=#{e.class}: #{e.message}")
    apply_lead_whatsapp_notice!(
      "O bloco do WhatsApp não pôde ser carregado agora. O lead permanece disponível; revise pendências da integração ou da conversa.",
      detail: e.message
    )
  end

  def apply_lead_whatsapp_notice!(message, detail: nil)
    @lead_whatsapp_panel_enabled = true if @lead_whatsapp_panel_enabled.nil?
    @whatsapp_conversation = nil
    @lead_activation_template = nil
    @whatsapp_templates = []
    @whatsapp_messages = []
    @whatsapp_summary = { pending_count: 0, failed_count: 0, media_count: 0, last_activity_at: nil }
    @whatsapp_thread_context_locals = {}
    @lead_whatsapp_notice = message
    @lead_whatsapp_notice_detail = detail
  end

  def apply_lead_whatsapp_disabled!
    @whatsapp_conversation = nil
    @lead_activation_template = nil
    @whatsapp_templates = []
    @whatsapp_messages = []
    @whatsapp_summary = { pending_count: 0, failed_count: 0, media_count: 0, last_activity_at: nil }
    @whatsapp_thread_context_locals = {}
    @lead_whatsapp_notice = nil
    @lead_whatsapp_notice_detail = nil
  end

  def approved_lead_whatsapp_templates(integration)
    templates = [@lead_activation_template]
    templates += Whatsapp::LeadConversationTemplates.names.map do |name|
      Whatsapp::LeadConversationTemplates.for(tenant: current_tenant, integration:, name:)
    end

    templates.compact.select { |template| template.persisted? && template.approved? }
  end

  def auto_open_lead_whatsapp_conversation?(_integration)
    can?(:view, :whatsapp_inbox) &&
      @lead.whatsapp_recipient.present?
  end

  def attach_activation_template_header!(message)
    return unless current_admin_user&.avatar&.attached?

    message.media_file.attach(current_admin_user.avatar.blob)
  end

  def activation_template_components(template, variables, message)
    Whatsapp::TemplateMessageComponents.call(
      template: template,
      variables: variables,
      client: Whatsapp::CloudClient.new(WhatsappBusinessIntegration.current(current_tenant)),
      header_media_attachable: message.media_file.attached? ? message.media_file : nil
    )
  end

  def lead_whatsapp_panel_messages(conversation)
    messages = conversation.messages.visible.ordered.last(100)
    latest_accepted_outbound_at = messages
      .select { |message| whatsapp_message_accepted_by_meta?(message) }
      .filter_map(&:created_at)
      .max
    return messages unless latest_accepted_outbound_at

    messages.reject do |message|
      stale_whatsapp_setup_failure?(message, latest_accepted_outbound_at)
    end
  end

  def lead_whatsapp_thread_context(snapshot)
    context = snapshot.to_h
    return context if context[:thread_lead]&.id == @lead.id

    context.merge(
      thread_lead: @lead,
      thread_property: current_tenant.habitations.find_by(id: @lead.property_id),
      thread_next_task: lead_whatsapp_next_task,
      thread_actions_summary: {
        tasks: @lead.tasks.where(status: "pendente").count,
        appointments: @lead.appointments.count,
        proposals: @lead.proposals.count
      }
    )
  end

  def lead_whatsapp_next_task
    tasks = @lead.tasks.includes(:admin_user).ordered.limit(20).to_a
    tasks.select(&:pendente?).find { |task| task.due_at.present? } || tasks.find(&:pendente?)
  end

  def whatsapp_message_accepted_by_meta?(message)
    message.outbound? &&
      message.wa_message_id.present? &&
      %w[sent delivered read].include?(message.status.to_s)
  end

  def stale_whatsapp_setup_failure?(message, latest_accepted_outbound_at)
    message.outbound? &&
      message.failed? &&
      message.wa_message_id.blank? &&
      message.created_at < latest_accepted_outbound_at &&
      message.error_message.to_s.match?(/integra[cç][aã]o n[aã]o configurada/i)
  end

  def safe_return_path(value)
    path = value.to_s
    return nil if path.blank?
    return nil unless path.start_with?("/")
    return nil if path.start_with?("//")

    path
  end

  # O lead ainda pertence ao corretor que clicou (não expirou/redistribuiu)?
  def lead_still_mine?(lead)
    lead.admin_user_id.present? && lead.admin_user_id == current_admin_user&.id
  end

  # Lead de Shark Tank ainda disponível para reivindicação (sem dono, aguardando).
  def shark_tank_open?(lead)
    current_admin_user.present? &&
      Lead.status_value(lead.status) == Lead.status_value(:waiting_acceptance)
  end

  # Abre o destino conforme a config (inbox interno, WhatsApp direto ou tela do lead).
  def open_attended_lead(lead)
    integration = WhatsappBusinessIntegration.current(current_tenant)
    inbox_attendance = integration.present? && integration.try(:inbox_attendance_enabled?) &&
      integration.messaging_ready? && can?(:view, :whatsapp_inbox)

    if inbox_attendance && lead.whatsapp_recipient.present?
      conversation = find_or_create_whatsapp_conversation_for!(lead)
      route_options = { lead_id: lead.id }
      redirect_to admin_whatsapp_conversation_path(conversation, route_options)
    elsif LeadSetting.instance(tenant: lead.tenant).open_whatsapp_on_click? && lead.direct_whatsapp_url.present?
      redirect_to lead.direct_whatsapp_url, allow_other_host: true
    else
      redirect_to admin_lead_path(lead)
    end
  end

  # Aceita o lead ao abrir: passa de "Aguardando Aceite" para "Em Atendimento",
  # travando o PocketExpirationJob (que só redistribui se ainda waiting_acceptance).
  # Transição atômica: revalida dono+status sob with_lock (mesma linha que o
  # PocketExpirationService trava), sem sobrescrever um lead já redistribuído.
  # Retorna false apenas quando o corretor perdeu a corrida.
  def accept_lead!(lead)
    return true unless Lead.status_value(lead.status) == Lead.status_value(:waiting_acceptance)

    accepted = false
    lead.with_lock do
      still_mine = lead.admin_user_id.present? && lead.admin_user_id == current_admin_user&.id
      still_waiting = Lead.status_value(lead.status) == Lead.status_value(:waiting_acceptance)
      accepted = still_mine && still_waiting && lead.update(status: Lead.status_value(:em_atendimento))
    end

    if accepted
      lead.activities.create(kind: "accepted", metadata: { by: current_admin_user&.name }.compact)
      return true
    end

    # Sem transição, mas o lead continua deste corretor (ex.: clique repetido
    # já em atendimento) — segue o fluxo normal de abertura.
    lead.admin_user_id.present? && lead.admin_user_id == current_admin_user&.id
  end

  def can_destroy_lead?
    tenant_owner?
  end

  def authorize_lead_access!
    return if accessible_lead_scope_for_current_user.where(id: @lead.id).exists?

    respond_to do |format|
      format.html { redirect_to admin_leads_path, alert: "Você não tem acesso a este lead." }
      format.json do
        render(
          json: {
            error: "lead_unavailable",
            message: "Este lead saiu da sua fila ou expirou. Atualize o Kanban."
          },
          status: :not_found
        )
      end
    end
  end

  # Cadastro manual: o form é completo, então permite os campos de contato e
  # qualificação — ao contrário do update, que só mexe em status/notas/dono.
  # admin_user_id fica FORA da permit list de propósito: o dono é decidido por
  # resolved_owner_id_for_new_lead, nunca pelo que veio no request.
  def new_lead_params
    attributes = params.require(:lead).permit(
      :name, :email, :phone,
      :status, :origin, :product, :lead_type, :lead_pipeline_id, :lead_pipeline_stage_id,
      :notes, :tags
    )

    attributes[:status] = Lead.status_value(attributes[:status], tenant: current_tenant)
    normalize_pipeline_params!(attributes)
    attributes[:origin] = attributes[:origin].presence || MANUAL_LEAD_ORIGIN
    # tags: o model já parseia string separada por vírgula (normalize_tags_value).

    property_id = resolved_property_id_for_new_lead
    attributes[:property_id] = property_id if property_id

    attributes
  end

  # Imóvel de interesse é informado pelo CÓDIGO (é assim que o operador conhece
  # o imóvel: "REF: 4664"), sempre resolvido dentro do tenant.
  def resolved_property_id_for_new_lead
    identifier = params.dig(:lead, :property_code).to_s.strip
    return nil if identifier.blank?

    scope = current_tenant.habitations
    habitation = scope.find_by(codigo: identifier)
    habitation ||= scope.find_by(id: identifier) if identifier.match?(/\A\d+\z/)
    @unresolved_property_code = identifier if habitation.nil?
    habitation&.id
  end

  # Código de imóvel inexistente não derruba o cadastro (o lead é o que importa),
  # mas o operador precisa saber que o vínculo não foi feito — falhar calado aqui
  # viraria lead "sem imóvel" sem explicação.
  def lead_created_notice
    return "Lead cadastrado com sucesso." if @unresolved_property_code.blank?

    "Lead cadastrado, mas nenhum imóvel com o código \"#{@unresolved_property_code}\" foi encontrado — o lead ficou sem imóvel de interesse."
  end

  # Dono do lead novo: por padrão quem criou. Só quem tem escopo além de
  # "próprios" (gestor da subárvore / conta) pode nascer com outro dono, e ainda
  # assim restrito a permitted_admin_user_ids_for_leads. Corretor sempre vira
  # dono do que cadastra.
  def resolved_owner_id_for_new_lead
    return current_admin_user&.id unless can_assign_lead_owner?

    requested = params.dig(:lead, :admin_user_id).presence
    return current_admin_user&.id if requested.blank?
    return current_admin_user&.id if permitted_admin_user_ids_for_leads.exclude?(requested.to_i)

    requested.to_i
  end

  def can_assign_lead_owner?
    return false unless current_admin_user

    tenant_owner? || current_admin_user.scope_for(:leads) != "own"
  end

  # Transferir é uma ação do dono do lead, não um privilégio administrativo:
  # quem tem escopo "own" ainda pode passar o PRÓPRIO lead pra frente (ex.:
  # sair de férias, repassar pra outro corretor). Escopo além de "own" (ou
  # tenant_owner) libera transferir qualquer lead, igual já fazia antes.
  def can_transfer_lead?(lead)
    return false unless current_admin_user
    return false unless can?(:edit, :leads)
    return true if tenant_owner? || current_admin_user.scope_for(:leads) != "own"

    lead.present? && lead.admin_user_id == current_admin_user.id
  end
  helper_method :can_transfer_lead?

  # Lista de destinatários pro modal/select de transferência. Quem já tem
  # escopo além de "own" (ou é tenant_owner) usa a mesma lista de sempre
  # (@broker_options). Corretor com escopo "own" transferindo o PRÓPRIO lead
  # pode escolher qualquer usuário ativo da conta — a restrição de escopo é
  # sobre quem ele enxerga/gerencia no dia a dia, não sobre pra quem ele pode
  # repassar algo que já é dele.
  def transfer_broker_options(lead)
    return @broker_options if current_admin_user&.scope_for(:leads) != "own"
    return @broker_options unless lead.present? && lead.admin_user_id == current_admin_user&.id

    current_tenant.admin_users.active.order(:name).pluck(:name, :id)
  end
  helper_method :transfer_broker_options

  def valid_transfer_target?(admin_user_id)
    return true if permitted_admin_user_ids_for_leads.include?(admin_user_id.to_i)
    return false unless current_admin_user&.scope_for(:leads) == "own" && @lead&.admin_user_id == current_admin_user.id

    current_tenant.admin_users.active.where(id: admin_user_id).exists?
  end

  def lead_contact_kind_label(activity)
    CONTACT_KIND_LABELS[activity.meta("contact_kind").to_s] || "Anotação interna"
  end

  def lead_contact_result_label(activity)
    CONTACT_RESULT_LABELS[activity.meta("contact_result").to_s]
  end

  def lead_unsuccessful_attempt_count(lead)
    return 0 unless lead

    since = lead_stage_entered_at(lead) || lead.created_at
    last_customer_at = lead.activities.where(kind: Leads::PipelineStageAutoAdvanceService::CUSTOMER_ACTIVITY_KINDS)
                           .where("created_at >= ?", since)
                           .maximum(:created_at) || since
    lead.activities.unsuccessful_contact_attempts.where("created_at >= ?", last_customer_at).count
  end

  def lead_stage_entered_at(lead)
    lead.lead_audit_logs
      .where(action: "status_changed")
      .order(created_at: :desc)
      .limit(1)
      .pick(:created_at) || lead.created_at
  end

  def lead_params
    permitted = [:status, :notes, :lead_pipeline_id, :lead_pipeline_stage_id]
    # Transferir: dono do lead sempre pode passar pra frente; reatribuir o
    # lead de outra pessoa exige escopo além de "own" (ou ser tenant_owner).
    permitted << :admin_user_id if can_transfer_lead?(@lead)
    # Parecer: nota interna visível/editável só pelo time administrativo.
    permitted << :parecer if current_admin_user&.admin?
    if lead_stage_qualification_enabled?
      permitted << @lead.qualification_field_for(current_admin_user)
      permitted << :qualification_note
    end
    attributes = params.require(:lead).permit(permitted)

    if attributes[:admin_user_id].present? && !valid_transfer_target?(attributes[:admin_user_id])
      attributes.delete(:admin_user_id)
    end
    normalize_pipeline_params!(attributes)
    normalize_qualification_params!(attributes)

    attributes
  end

  def lead_stage_qualification_enabled?
    @lead.lead_pipeline_stage&.policy&.qualification_enabled?
  end

  def normalize_qualification_params!(attributes)
    qualification_key = @lead.qualification_field_for(current_admin_user).to_s
    return unless attributes.key?(qualification_key)

    attributes[qualification_key] = attributes[qualification_key].presence
    attributes[:qualification_note] = attributes[:qualification_note].to_s.squish.presence if attributes.key?(:qualification_note)
  end

  def allowed_lead_qualification?(attributes)
    qualification_key = @lead.qualification_field_for(current_admin_user).to_s
    return true unless attributes.key?(qualification_key)

    policy = @lead.lead_pipeline_stage&.policy
    return false unless policy&.qualification_enabled?

    value = attributes[qualification_key].presence
    value.blank? || Array(policy.qualification_options).include?(value)
  end

  def log_qualification_change!
    LeadActivity.log!(
      lead: @lead,
      kind: "qualification_updated",
      metadata: {
        broker_qualification_status: @lead.broker_qualification_status,
        manager_qualification_status: @lead.manager_qualification_status,
        divergent: @lead.qualification_divergent?,
        by: current_admin_user&.name
      }.compact
    )
  end

  def load_lead_pipeline_context
    @lead_pipelines = current_tenant.lead_pipelines.active.ordered.to_a
    @selected_pipeline = if params[:lead_pipeline_id].present?
      current_tenant.lead_pipelines.find(params[:lead_pipeline_id])
    elsif @lead&.lead_pipeline.present?
      @lead.lead_pipeline
    elsif action_name.in?(%w[new create])
      LeadPipeline.ensure_default!(tenant: current_tenant)
    end
    if @lead_pipelines.blank? || (@selected_pipeline.present? && @lead_pipelines.exclude?(@selected_pipeline))
      @lead_pipelines = current_tenant.lead_pipelines.active.ordered.to_a
    end
    @pipeline_options = @lead_pipelines.map { |pipeline| [pipeline.name, pipeline.id] }
  end

  def normalize_pipeline_params!(attributes)
    pipeline_change_requested = action_name.in?(%w[new create]) ||
                                attributes[:lead_pipeline_id].present? ||
                                attributes[:lead_pipeline_stage_id].present? ||
                                attributes[:status].present?
    return unless pipeline_change_requested

    pipeline = current_tenant.lead_pipelines.find_by(id: attributes[:lead_pipeline_id].presence) || @selected_pipeline
    stage = pipeline&.stages&.find_by(id: attributes[:lead_pipeline_stage_id].presence)
    stage ||= LeadPipelineStage.matching_name(tenant: current_tenant, pipeline: pipeline, name: attributes[:status]) if attributes[:status].present?
    stage ||= pipeline&.default_stage

    attributes[:lead_pipeline_id] = pipeline.id if pipeline
    attributes[:lead_pipeline_stage_id] = stage.id if stage
    attributes[:status] = stage.name if stage
  end

  def allowed_stage_transition?(attributes)
    current_stage = @lead.lead_pipeline_stage
    next_stage_id = attributes[:lead_pipeline_stage_id].presence
    return true if current_stage.blank? || next_stage_id.blank? || current_stage.id.to_s == next_stage_id.to_s

    next_stage = current_tenant.lead_pipeline_stages.find_by(id: next_stage_id)
    return false if next_stage.present? && !next_stage.visible_to_admin_user?(current_admin_user)

    transitions = current_stage.transitions
    return true unless transitions.exists?

    transitions.exists?(next_stage_id: next_stage_id)
  end

  def load_origin_options
    option_scope = lead_scope_for_current_user.reorder(nil)
    @origin_options = Lead.origin_options(scope: option_scope, tenant: current_tenant)
    @tag_options = Lead.tag_options(scope: option_scope)
    @status_options = lead_status_options_for_selected_context
    @lead_stage_color_by_status = lead_stage_color_map
    @broker_options = permitted_admin_users_for_leads.order(:name).pluck(:name, :id)
    @lead_pipeline_stage_options = lead_pipeline_stage_options_for_filter
    @lead_archive_reason_options = current_tenant.attribute_options.for_context("lead").for_category("archive_reason").ordered.pluck(:name, :id)
  end

  def lead_pipeline_stage_options_for_filter
    scope = if @selected_pipeline.present?
      @selected_pipeline.stages.active.ordered.includes(:lead_pipeline)
    else
      current_tenant.lead_pipeline_stages.active.ordered.includes(:lead_pipeline)
    end

    visible_stages_for(scope).map do |stage|
      label = @selected_pipeline.present? ? stage.name : [stage.lead_pipeline&.name, stage.name].compact_blank.join(" · ")
      [label, stage.id]
    end
  end

  def lead_stage_color_map
    scope = if @selected_pipeline.present?
      @selected_pipeline.stages.active.ordered
    else
      current_tenant.lead_pipeline_stages.active.ordered
    end

    visible_stages_for(scope).index_by(&:name).transform_values(&:display_color)
  end

  def load_pwa_leads_context(filtered_scope, unfiltered_scope: nil)
    @pwa_lead_tab = params[:mobile_tab].presence_in(%w[todo visits future favorites all]) || "todo"
    @pwa_queue_position = current_user_distribution_queue_position

    base_scope = filtered_scope.where(admin_user_id: current_admin_user&.id)
    list_base_scope = hide_discarded_from_list_scope(base_scope)
    original_scope = (unfiltered_scope || filtered_scope).where(admin_user_id: current_admin_user&.id)
    @pwa_tab_counts = lead_tab_counts_for(list_base_scope)
    @pwa_tab_original_counts = lead_tab_counts_for(hide_discarded_from_list_scope(original_scope))

    @pwa_leads = pwa_lead_scope_for_tab(list_base_scope, @pwa_lead_tab)
                 .includes(:admin_user, lead_labelings: :lead_label)
                 .order(updated_at: :desc, created_at: :desc)
                 .limit(PWA_LEAD_LIST_PAGE_SIZE)
                 .to_a
    load_pwa_kanban_context(base_scope)
    load_pwa_lead_activity_context((@pwa_leads + @pwa_kanban_leads).uniq)
  end

  def load_pwa_kanban_context(base_scope)
    pwa_tab_scope = pwa_lead_scope_for_tab(base_scope, "all")
    @pwa_kanban_statuses = lead_statuses_for_kanban(pwa_tab_scope)
    @pwa_kanban_leads_by_status = @pwa_kanban_statuses.index_with { [] }
    @pwa_kanban_counts_by_status = Hash.new(0)
    @pwa_kanban_total_count = pwa_tab_scope.reorder(nil).count

    pwa_tab_scope.reorder(nil).group(:status).count.each do |status, count|
      status = Lead.status_value(status, tenant: current_tenant)
      next if @selected_pipeline.present? && !@pwa_kanban_leads_by_status.key?(status)

      @pwa_kanban_counts_by_status[status] += count
    end
    @pwa_kanban_statuses.each { |status| @pwa_kanban_counts_by_status[status] ||= 0 }

    ranked = pwa_tab_scope.reorder(nil).select(
      "leads.*, ROW_NUMBER() OVER (PARTITION BY leads.status ORDER BY leads.updated_at DESC, leads.created_at DESC) AS pwa_kanban_rank"
    )
    @pwa_kanban_leads = Lead.from(ranked, :leads)
                            .where("pwa_kanban_rank <= ?", PWA_LEAD_KANBAN_COLUMN_SIZE)
                            .includes(:admin_user, lead_labelings: :lead_label)
                            .order(updated_at: :desc, created_at: :desc)
                            .to_a
    @pwa_kanban_leads.each do |lead|
      status = Lead.status_value(lead.status, tenant: current_tenant)
      next if @selected_pipeline.present? && !@pwa_kanban_leads_by_status.key?(status)

      @pwa_kanban_leads_by_status[status] ||= []
      @pwa_kanban_leads_by_status[status] << lead
    end
    @pwa_kanban_column_size = PWA_LEAD_KANBAN_COLUMN_SIZE
  end

  def pwa_lead_scope_for_tab(base_scope, tab)
    lead_scope_for_tab(base_scope, tab)
  end

  def lead_tab_counts_for(base_scope)
    {
      "todo" => lead_scope_for_tab(base_scope, "todo").reorder(nil).count,
      "visits" => lead_scope_for_tab(base_scope, "visits").reorder(nil).count,
      "future" => lead_scope_for_tab(base_scope, "future").reorder(nil).count,
      "favorites" => lead_scope_for_tab(base_scope, "favorites").reorder(nil).count,
      "all" => lead_scope_for_tab(base_scope, "all").reorder(nil).count
    }
  end

  def lead_scope_for_tab(base_scope, tab)
    case tab
    when "todo"
      pwa_actionable_leads(base_scope)
    when "visits"
      base_scope.where(id: pwa_future_visit_lead_ids(base_scope))
    when "future"
      pwa_scheduled_leads(base_scope)
    when "favorites"
      base_scope.joins(:lead_favorites).where(lead_favorites: { admin_user_id: current_admin_user&.id })
    else
      base_scope
    end
  end

  def pwa_actionable_leads(base_scope)
    base_scope
      .where(status: active_lead_status_values_with_blank)
      .where(
        "leads.id IN (:due_task_ids) OR (leads.status IN (:priority_statuses) AND leads.id NOT IN (:scheduled_later_ids))",
        due_task_ids: pwa_due_task_lead_ids(base_scope),
        priority_statuses: pwa_priority_lead_status_values,
        scheduled_later_ids: pwa_later_scheduled_lead_ids(base_scope)
      )
  end

  def pwa_future_visit_lead_ids(base_scope)
    appointment_ids = Appointment
      .where(tenant_id: current_tenant.id, admin_user_id: current_admin_user&.id, kind: "visita", status: "agendado")
      .select(:lead_id)

    base_scope
      .where("leads.status IS NULL OR leads.status NOT IN (?)", pwa_future_excluded_status_values)
      .where("leads.id IN (:appointment_ids) OR leads.id IN (:external_visit_ids)",
             appointment_ids: appointment_ids,
             external_visit_ids: pwa_external_schedule_lead_ids(base_scope, visits: true, timing: :scheduled))
      .select(:id)
  end

  def pwa_due_task_lead_ids(base_scope)
    task_ids = Task
      .where(tenant_id: current_tenant.id, admin_user_id: current_admin_user&.id)
      .pendentes
      .where("due_at IS NULL OR tasks.lead_id NOT IN (:scheduled_lead_ids)", scheduled_lead_ids: pwa_later_scheduled_lead_ids(base_scope))
      .select(:lead_id)

    base_scope
      .where(id: task_ids)
      .select(:id)
  end

  def pwa_later_scheduled_lead_ids(base_scope)
    base_scope
      .where(
        "leads.id IN (:future_ids) OR leads.id IN (:visit_ids)",
        future_ids: pwa_scheduled_leads(base_scope).select(:id),
        visit_ids: pwa_future_visit_lead_ids(base_scope)
      )
      .select(:id)
  end

  def pwa_scheduled_leads(base_scope)
    task_ids = Task
      .where(tenant_id: current_tenant.id, admin_user_id: current_admin_user&.id)
      .pendentes
      .where.not(due_at: nil)
      .select(:lead_id)

    base_scope
      .where("leads.status IS NULL OR leads.status NOT IN (?)", pwa_future_excluded_status_values)
      .where(
        "leads.id IN (:task_ids) OR leads.id IN (:external_task_ids)",
        task_ids: task_ids,
        external_task_ids: pwa_external_schedule_lead_ids(base_scope, visits: false, timing: :scheduled)
      )
  end

  def pwa_future_excluded_status_values
    pipeline_statuses = current_tenant.lead_pipeline_stages.active.where(stage_type: %w[lost archived]).pluck(:name)
    (pipeline_statuses + [Lead.status_value(:descartado), "Descartado", "Perdido", "Arquivado"]).compact_blank.uniq
  end

  def pwa_external_schedule_lead_ids(base_scope, visits:, timing:)
    scope = pwa_external_schedule_scope(base_scope, visits: visits)
    scope =
      case timing
      when :upcoming
        scope.where("#{EXTERNAL_SCHEDULE_DATE_SQL} >= ?", Time.current.beginning_of_day)
      when :scheduled
        scope
      else
        scope
    end
    scope.select(:lead_id)
  end

  def pwa_external_schedule_scope(base_scope, visits:)
    scope = LeadActivity
            .where(kind: EXTERNAL_SCHEDULE_KIND, lead_id: base_scope.select(:id))
            .where("NULLIF(COALESCE(lead_activities.metadata #>> '{raw,schedulated_action_date}', lead_activities.metadata #>> '{raw,due_at}', lead_activities.metadata #>> '{raw,scheduled_at}', lead_activities.metadata #>> '{raw,date}', lead_activities.metadata #>> '{raw,datetime}', lead_activities.metadata ->> 'due_at'), '') IS NOT NULL")
            .where("NOT #{EXTERNAL_CLOSED_SCHEDULE_SQL}")
    visits ? scope.where(EXTERNAL_VISIT_SCHEDULE_SQL) : scope.where("NOT #{EXTERNAL_VISIT_SCHEDULE_SQL}")
  end

  def load_pwa_lead_activity_context(leads)
    lead_ids = leads.map(&:id)
    @pwa_contacted_lead_ids = LeadActivity.where(lead_id: lead_ids, kind: CONTACT_ACTIVITY_KINDS).distinct.pluck(:lead_id)
    @pwa_next_tasks_by_lead_id = Task
                                  .where(tenant_id: current_tenant.id, lead_id: lead_ids, admin_user_id: current_admin_user&.id)
                                  .pendentes
                                  .order(Arel.sql("due_at ASC NULLS FIRST"), :created_at)
                                  .to_a
                                  .group_by(&:lead_id)
    @pwa_next_visits_by_lead_id = Appointment
                                   .where(tenant_id: current_tenant.id, lead_id: lead_ids, admin_user_id: current_admin_user&.id, kind: "visita", status: "agendado")
                                   .ordered
                                   .to_a
                                   .group_by(&:lead_id)
    pwa_external_schedule_records_for(lead_ids).each do |action|
      target = action.kind == "visita" ? @pwa_next_visits_by_lead_id : @pwa_next_tasks_by_lead_id
      target[action.lead_id] ||= []
      target[action.lead_id].reject! { |item| action.task_id.present? && item.respond_to?(:id) && item.id == action.task_id.to_i }
      target[action.lead_id] << action
      target[action.lead_id].sort_by! { |item| pwa_schedule_sort_time(item) || Time.zone.at(0) }
    end
    @pwa_favorite_lead_ids = current_admin_user
                             .lead_favorites
                             .where(lead_id: lead_ids)
                             .pluck(:lead_id)
  end

  def pwa_external_schedule_records_for(lead_ids)
    return [] if lead_ids.blank?

    LeadActivity
      .where(kind: EXTERNAL_SCHEDULE_KIND, lead_id: lead_ids)
      .where("NULLIF(COALESCE(lead_activities.metadata #>> '{raw,schedulated_action_date}', lead_activities.metadata #>> '{raw,due_at}', lead_activities.metadata #>> '{raw,scheduled_at}', lead_activities.metadata #>> '{raw,date}', lead_activities.metadata #>> '{raw,datetime}', lead_activities.metadata ->> 'due_at'), '') IS NOT NULL")
      .where("NOT #{EXTERNAL_CLOSED_SCHEDULE_SQL}")
      .pluck(:lead_id, :metadata)
      .filter_map { |lead_id, metadata| pwa_external_schedule_record(lead_id, metadata) }
  end

  def pwa_external_schedule_record(lead_id, metadata)
    raw = metadata["raw"].presence || {}
    due_at = parse_pwa_external_schedule_time(
      raw["schedulated_action_date"].presence ||
      raw["due_at"].presence ||
      raw["scheduled_at"].presence ||
      raw["date"].presence ||
      raw["datetime"].presence ||
      metadata["due_at"]
    )
    return nil if due_at.blank?

    title = raw["schedulated_action_name"].presence ||
      raw["name"].presence ||
      raw["title"].presence ||
      metadata["title"].presence ||
      "Ação agendada"
    text = [
      raw["schedulated_action_name"],
      raw["schedulated_action_type_alias"],
      raw["name"],
      raw["title"],
      raw["alias"],
      raw["type"],
      metadata["title"]
    ].compact.join(" ").parameterize(separator: "_")
    kind = (text.include?("visita") || text.include?("scheduled_visit") || text.include?("reuniao")) ? "visita" : "follow_up"
    PwaExternalSchedule.new(lead_id: lead_id, title: title, kind: kind, due_at: due_at, task_id: metadata["task_id"])
  end

  def pwa_schedule_sort_time(item)
    return item.due_at if item.respond_to?(:due_at)
    return item.starts_at if item.respond_to?(:starts_at)

    nil
  end

  def parse_pwa_external_schedule_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def load_lead_favorite_context
    @lead_favorited = current_admin_user&.lead_favorites&.exists?(lead_id: @lead.id)
  end

  def current_user_distribution_queue_position
    return nil if current_admin_user.blank?

    rules = current_user_distribution_queue_rules.to_a
    agents_by_rule_id = DistributionRuleAgent
      .where(tenant_id: current_tenant.id, distribution_rule_id: rules.map(&:id))
      .order(:position, :id)
      .to_a
      .group_by(&:distribution_rule_id)

    rules
      .map do |rule|
        agents = agents_by_rule_id[rule.id] || []
        display_queue_position_for_agents(agents, current_admin_user.id)
      end
      .compact
      .min
  end

  def display_queue_position_for_agents(agents, admin_user_id)
    index = agents.find_index { |agent| agent.admin_user_id == admin_user_id }
    index.present? ? index + 1 : nil
  end

  def display_queue_positions_by_agent_id(agents)
    agents
      .group_by(&:distribution_rule_id)
      .flat_map do |_rule_id, rule_agents|
        rule_agents.each_with_index.map { |agent, index| [agent.id, index + 1] }
      end
      .to_h
  end

  def current_user_distribution_queue_rules
    return current_tenant.distribution_rules.none if current_admin_user.blank?

    scope = operational_distribution_rules
      .joins(:distribution_rule_agents)
      .where(distribution_rule_agents: { admin_user_id: current_admin_user.id })
      .distinct

    if DistributionRule.column_names.include?("pocket_to_shark_tank")
      scope.where(
        "distribution_rules.distribution_mode = :shark_tank OR distribution_rules.pocket_to_shark_tank = TRUE",
        shark_tank: DistributionRule.distribution_modes.fetch("shark_tank")
      )
    else
      scope.where(distribution_mode: DistributionRule.distribution_modes.fetch("shark_tank"))
    end
  end

  def operational_distribution_rules
    scope = current_tenant.distribution_rules.active
    return scope unless defined?(ExternalLeadIntegration)

    scope
      .where.not(name: ExternalLeadIntegration::SUPPORT_RULE_NAME)
      .where(
        "NOT (COALESCE(distribution_rules.webhook_tags, '[]'::jsonb) ? :internal_webhook_tag)",
        internal_webhook_tag: ExternalLeadIntegration::WEBHOOK_TAG
      )
  end

  def lead_status_options_for_selected_context
    if @selected_pipeline.present?
      visible = visible_stages_for(@selected_pipeline.stages.active.ordered)
      return visible.map { |stage| Lead.status_value(stage.name, tenant: current_tenant) }.compact_blank.uniq if visible.any?

      return Lead.status_options(pipeline: @selected_pipeline, tenant: current_tenant)
        .map { |status| Lead.status_value(status, tenant: current_tenant) }
        .compact_blank
        .uniq
    end

    pipeline_statuses = visible_stages_for(current_tenant.lead_pipeline_stages.active.ordered).map(&:name)
    existing_statuses = lead_scope_for_current_user.reorder(nil).distinct.pluck(:status).compact
    (pipeline_statuses + existing_statuses + Lead::LEGACY_STATUSES)
      .map { |status| Lead.status_value(status, tenant: current_tenant) }
      .compact_blank
      .uniq
  end

  def lead_statuses_for_kanban(lead_scope)
    configured_statuses = lead_status_options_for_selected_context
    return visible_kanban_statuses(@status_filters) if @status_filters.present?
    return visible_kanban_statuses(configured_statuses) if @selected_pipeline.present?

    visible_kanban_statuses(configured_statuses + lead_scope.reorder(nil).distinct.pluck(:status).compact)
  end

  def status_filter_values_for(status)
    canonical = Lead.status_value(status, tenant: current_tenant)
    values = [canonical]
    values << Lead::DEFAULT_STATUS if canonical == Lead.default_status(tenant: current_tenant) && Lead::DEFAULT_STATUS != canonical
    values.uniq
  end

  def visible_kanban_statuses(statuses)
    statuses
      .map { |status| Lead.status_value(status, tenant: current_tenant) }
      .compact_blank
      .uniq
      .excluding(*hidden_kanban_status_values)
  end

  def hidden_kanban_status_values
    HIDDEN_KANBAN_STATUSES.map { |status| Lead.status_value(status, tenant: current_tenant) }.uniq
  end

  def visible_stages_for(scope)
    stages = scope.respond_to?(:includes) ? scope.includes(:policy).to_a : Array(scope)
    return stages if current_admin_user&.admin?

    stages.select { |stage| stage.visible_to_admin_user?(current_admin_user) }
  end
  helper_method :visible_stages_for

  def actionable_lead_tasks(tasks)
    tasks.reject { |task| non_actionable_lead_task?(task) }
  end

  def non_actionable_lead_task?(task)
    title = task.title.to_s.squish
    title.match?(/\A(notificar corretor sobre oportunidade|oportunidade de interesse para)\b/i)
  end

  def lead_scope_for_current_user
    return Lead.none unless current_admin_user

    owner_ids = visible_owner_ids(:leads)
    return current_tenant.leads if owner_ids.nil? # escopo "all"/admin dentro do Tenant

    scope = current_tenant.leads.where(admin_user_id: owner_ids)
    # Ao ver a equipe, mantém o recorte por tipo de atuação (venda/locação) do gestor.
    scope = filter_leads_by_acting_type(scope) if include_team?(:leads)
    scope
  end

  def accessible_lead_scope_for_current_user
    return Lead.none unless current_admin_user

    owner_ids = accessible_owner_ids(:leads)
    return current_tenant.leads if owner_ids.nil?

    current_tenant.leads.where(admin_user_id: owner_ids)
  end

  # Recorte adicional por acting_type — preservado por cima do escopo de equipe.
  def filter_leads_by_acting_type(scope)
    case current_admin_user.acting_type
    when "sales"
      scope.joins(:admin_user).where(admin_users: { acting_type: %i[sales both] })
    when "rentals"
      scope.joins(:admin_user).where(admin_users: { acting_type: %i[rentals both] })
    else
      scope
    end
  end

  def permitted_admin_users_for_leads
    return AdminUser.none unless current_admin_user
    return current_tenant.admin_users.active if owns_all_resource?(:leads)

    if current_admin_user.can_view_team?(:leads)
      scope = current_tenant.admin_users.active.where(id: current_admin_user.team_scope_ids)
      return filter_users_by_acting_type(scope)
    end

    current_tenant.admin_users.active.where(id: current_admin_user.id)
  end

  def filter_users_by_acting_type(scope)
    case current_admin_user.acting_type
    when "sales"
      scope.where(acting_type: %i[sales both])
    when "rentals"
      scope.where(acting_type: %i[rentals both])
    else
      scope
    end
  end

  def permitted_admin_user_ids_for_leads
    permitted_admin_users_for_leads.pluck(:id)
  end

  def load_show_context
    @page_title = "Lead: #{@lead.name}"
    @property = current_tenant.habitations.find_by(id: @lead.property_id)
    @lead_audit_logs = @lead.lead_audit_logs.includes(:admin_user).recent.limit(80)
    @push_delivery_events = push_delivery_events_for(@lead)
    @timeline = lead_timeline_events_for(@lead, @push_delivery_events)
    @contact_history_activities = @lead.activities.where(kind: "note").recent.limit(40)
    @tasks = @lead.tasks.includes(:admin_user).ordered.limit(50)
    @actionable_tasks = actionable_lead_tasks(@tasks)
    @next_task = @actionable_tasks.select(&:pendente?).find { |task| task.due_at.present? } ||
                 @actionable_tasks.find(&:pendente?)
    @appointments = @lead.appointments.upcoming.limit(20)
    @proposals = @lead.proposals.ordered.limit(20)
    load_proposal_modal_context
    @archive_reason_options = archive_reason_options_for(@lead)
    @funnel_statuses = Lead.status_options(pipeline: @lead.lead_pipeline || @selected_pipeline, tenant: current_tenant)
    load_lead_whatsapp_context
    @property_share_collections = @lead.ai_property_share_collections.includes(:admin_user, :habitations).order(created_at: :desc).limit(12)
    @shared_interest_property_ids = @lead.shared_property_ids
    @shared_interest_property_statuses = @lead.shared_property_statuses
    load_origin_options
    @interest_settings = InterestIntelligence::Settings.current
    load_lead_favorite_context
  end

  def push_delivery_events_for(lead)
    PushDeliveryEvent
      .where(lead_id: lead.id)
      .includes(:admin_user, :push_subscription)
      .order(created_at: :desc)
      .limit(20)
  end

  def lead_timeline_events_for(lead, push_delivery_events)
    (lead.activities.recent.limit(60).to_a + push_delivery_events.to_a)
      .sort_by(&:created_at)
      .reverse
      .first(80)
  end

  def load_proposal_modal_context
    return unless can?(:manage, :comercial)

    @proposal_habitations = current_tenant.habitations.order(updated_at: :desc).limit(500)
    @new_proposal = @lead.proposals.new(
      habitation_id: @lead.property_id,
      admin_user: current_admin_user,
      validade: 7.days.from_now.to_date
    )
  end

  def load_interest_intelligence
    @interest_settings = InterestIntelligence::Settings.current
    matcher = InterestIntelligence::Matcher.new(@lead)
    @interest_profile = matcher.profile
    @interest_profile_incomplete = matcher.profile_incomplete?
    @interest_matches = matcher.call
    @interest_navigation_events = @lead.public_navigation_events.includes(:habitation).recent.limit(12)
    @interest_property_interests = @lead.client_property_interests.includes(:habitation).order(Arel.sql("COALESCE(last_search_at, created_at) DESC")).limit(8)
  end
end
