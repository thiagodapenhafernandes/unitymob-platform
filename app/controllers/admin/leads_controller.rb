class Admin::LeadsController < Admin::BaseController
  # Kanban carrega em pequenos lotes por coluna para manter a tela responsiva.
  KANBAN_COLUMN_PAGE_SIZE = 5
  # Lista PWA de leads: carrega em lotes por aba (scroll infinito).
  PWA_LEAD_LIST_PAGE_SIZE = 15
  # Origem default do lead cadastrado na mão: separa do que veio de site/portal.
  MANUAL_LEAD_ORIGIN = "Cadastro manual".freeze
  CONTACT_ACTIVITY_KINDS = %w[
    accepted note whatsapp_out appointment_created appointment_done
    proposal_created proposal_sent proposal_viewed proposal_aceita proposal_recusada
  ].freeze
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
  # Editar exige permissão própria: antes o update só pedia :view + escopo do
  # registro, então quem enxergasse o lead podia alterá-lo (inclusive arrastar
  # no kanban). O recorte por registro continua vindo do authorize_lead_access!.
  before_action -> { check_permission!(:edit, :leads) }, only: [:update]
  before_action -> { check_permission!(:create, :leads) }, only: [:new, :create]
  helper_method :can_destroy_lead?, :can_assign_lead_owner?
  before_action :set_lead, only: [:show, :update, :destroy, :toggle_favorite, :log_contact, :reprocess_interest, :simulate_interest, :interest_intelligence, :open_whatsapp_conversation, :activate_whatsapp_template, :share_properties, :suggest_properties, :archive, :close_deal, :schedule_activity]
  before_action :authorize_lead_access!, only: [:show, :update, :destroy, :toggle_favorite, :log_contact, :reprocess_interest, :simulate_interest, :interest_intelligence, :open_whatsapp_conversation, :activate_whatsapp_template, :share_properties, :suggest_properties, :archive, :close_deal, :schedule_activity]
  before_action :load_lead_pipeline_context, only: [:index, :kanban_column, :pwa_leads_page, :new, :create, :show, :update]
  before_action :load_origin_options, only: [:index, :kanban_column, :pwa_leads_page, :new, :create, :show, :update]

  def index
    assign_lead_filter_state
    @view_mode = resolve_view_mode

    lead_scope = filtered_lead_scope_for_current_user

    stats_scope = lead_scope.reorder(nil)
    @total_leads = stats_scope.count
    @new_leads = stats_scope.where(status: Lead.status_value("Novo")).count
    @in_service_leads = stats_scope.where(status: Lead.status_value("Em Atendimento")).count
    @unassigned_leads = stats_scope.where(admin_user_id: nil).count
    @status_counts = stats_scope.group(:status).count
    @origin_counts = lead_scope_for_current_user.reorder(nil).where.not(origin: [nil, ""]).group(:origin).count

    lead_scope = lead_scope.includes(:admin_user, lead_labelings: :lead_label).order(created_at: :desc)

    @lead_statuses = if @status_filters.present?
                        @status_filters.map { |status| Lead.status_value(status, tenant: current_tenant) }.compact_blank
                      else
                        (lead_status_options_for_selected_context + lead_scope.reorder(nil).distinct.pluck(:status).compact).uniq
                      end
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
      @leads_by_status[Lead.status_value(lead.status)] ||= []
      @leads_by_status[Lead.status_value(lead.status)] << lead
    end
    # Contadores da coluna = total REAL (a coluna pode estar truncada no teto).
    @lead_counts_by_status = Hash.new(0)
    lead_scope.reorder(nil).group(:status).count.each do |status, count|
      @lead_counts_by_status[Lead.status_value(status)] += count
    end
    @lead_statuses.each { |status| @lead_counts_by_status[status] ||= 0 }
    @kanban_column_page_size = KANBAN_COLUMN_PAGE_SIZE
    @leads = lead_scope.paginate(page: params[:page], per_page: 20)
    load_pwa_leads_context(stats_scope)
    property_ids = (@kanban_leads + @leads.to_a + @pwa_leads.to_a).filter_map(&:property_id).uniq
    @properties_by_id = current_tenant.habitations.where(id: property_ids).index_by(&:id)
    @selected_lead = @kanban_leads.first || @leads.first
    @page_title = "Gerenciar Leads"
  end

  def kanban_column
    assign_lead_filter_state

    status = Lead.status_value(params[:status], tenant: current_tenant)
    offset = [params[:offset].to_i, 0].max
    lead_scope = filtered_lead_scope_for_current_user.where(leads: { status: status })
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
    base_scope = filtered_lead_scope_for_current_user.where(admin_user_id: current_admin_user&.id)
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
    @timeline = @lead.activities.recent.limit(60)
    @tasks = @lead.tasks.includes(:admin_user).ordered.limit(50)
    @actionable_tasks = actionable_lead_tasks(@tasks)
    @next_task = @actionable_tasks.select(&:pendente?).find { |task| task.due_at.present? } ||
                 @actionable_tasks.find(&:pendente?)
    @appointments = @lead.appointments.upcoming.limit(20)
    @proposals = @lead.proposals.ordered.limit(20)
    @archive_reason_options = archive_reason_options_for(@lead)
    @funnel_statuses = Lead.status_options
    load_lead_whatsapp_context
    @push_delivery_events = push_delivery_events_for(@lead)
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
      claimed = Lead.claim!(@lead.id, current_admin_user&.id)
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
    kind = params[:contact_kind].presence || "note"
    body = params[:body].to_s.strip
    LeadActivity.log!(lead: @lead, kind: "note", metadata: { contact_kind: kind, body: body, by: current_admin_user&.name }.compact)
    redirect_to admin_lead_path(@lead), notice: "Contato registrado."
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
    destination = params[:workspace].to_s == "focus" ? admin_whatsapp_conversation_path(conversation, workspace: "focus") : admin_whatsapp_conversation_path(conversation)
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
      redirect_to admin_lead_path(@lead), alert: "Selecione o tipo de atividade."
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
    host = tenant.tenant_domains.active.primary_first.first&.hostname
    host = host.to_s.delete_prefix("app.") if host.present?
    return "https://#{host}" if host.present?

    request.base_url.sub(%r{://app\.}, "://")
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
    @parsed_start_date = nil
    @parsed_end_date = nil
    @parsed_closed_start_date = nil
    @parsed_closed_end_date = nil
    @lead_filter_habitation_joined = false
  end

  def filtered_lead_scope_for_current_user
    scope = lead_scope_for_current_user

    if @q.present?
      term = "%#{ActiveRecord::Base.sanitize_sql_like(@q.to_s.strip)}%"
      scope = scope.where(
        "leads.name ILIKE :q OR leads.email ILIKE :q OR leads.phone ILIKE :q OR leads.client_name ILIKE :q OR leads.client_email ILIKE :q OR leads.client_phone ILIKE :q OR leads.origin ILIKE :q OR leads.product ILIKE :q",
        q: term
      )
    end

    scope = scope.where(leads: { lead_pipeline_id: @selected_pipeline.id }) if @selected_pipeline.present?
    scope = apply_status_filter(scope)
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
    scope = apply_closed_at_filter(scope)
    apply_created_at_filter(scope)
  end

  def apply_status_filter(scope)
    return scope if @status_filters.blank?

    values = @status_filters.map { |status| Lead.status_value(status, tenant: current_tenant) }.compact_blank
    values.present? ? scope.where(leads: { status: values }) : scope
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
        "leads.id NOT IN (#{LeadActivity.where(kind: CONTACT_ACTIVITY_KINDS).select(:lead_id).to_sql})"
      when "schedule_activity"
        "leads.id IN (#{Task.where(tenant_id: current_tenant.id).pendentes.select(:lead_id).to_sql}) OR leads.id IN (#{pwa_external_schedule_scope(scope, visits: false).select(:lead_id).to_sql})"
      when "return_customer"
        returning_tasks = Task.where(tenant_id: current_tenant.id).pendentes.where("LOWER(tasks.title) LIKE '%retornar%'").select(:lead_id)
        returning_external = pwa_external_schedule_scope(scope, visits: false).where("#{EXTERNAL_SCHEDULE_TEXT_SQL} LIKE '%retornar%' OR #{EXTERNAL_SCHEDULE_TEXT_SQL} LIKE '%feedback_customer%'").select(:lead_id)
        "leads.id IN (#{returning_tasks.to_sql}) OR leads.id IN (#{returning_external.to_sql})"
      when "scheduled_visit"
        appointments = Appointment.where(tenant_id: current_tenant.id, kind: "visita", status: "agendado").upcoming.select(:lead_id)
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

  def apply_attention_filter(scope)
    case @attention_filter.to_s
    when "requires_action"
      scope.where(status: active_lead_status_values_with_blank).where(attention_leads_sql)
    when "stalled"
      scope.where(status: active_lead_status_values_with_blank).where("leads.updated_at < ?", 2.days.ago)
    when "unassigned"
      scope.where(admin_user_id: nil, status: active_lead_status_values_with_blank)
    when "holding"
      scope.holding
    when "no_first_contact"
      scope.where(status: active_lead_status_values_with_blank)
        .where.not(id: LeadActivity.where(kind: CONTACT_ACTIVITY_KINDS).select(:lead_id))
    when "sla_overdue"
      scope.where(status: active_lead_status_values_with_blank)
        .where("leads.created_at < ?", first_contact_sla_hours.hours.ago)
        .where.not(id: LeadActivity.where(kind: CONTACT_ACTIVITY_KINDS).select(:lead_id))
    when "with_opportunity"
      scope.where(
        "leads.status = :closed OR leads.id IN (:appointment_ids) OR leads.id IN (:proposal_ids)",
        closed: Lead.status_value(:concluido),
        appointment_ids: Appointment.where(kind: "visita").select(:lead_id),
        proposal_ids: Proposal.where.not(status: "rascunho").select(:lead_id)
      )
    else
      scope
    end
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

    scope = scope.where(status: Lead.status_value(:concluido))
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
    Lead::LEGACY_STATUSES - [Lead.status_value(:descartado), Lead.status_value(:concluido)]
  end

  def active_lead_status_values_with_blank
    active_lead_status_values + [nil]
  end

  def attention_leads_sql
    ActiveRecord::Base.sanitize_sql_array([
      "leads.status = ? OR leads.admin_user_id IS NULL OR leads.updated_at < ?",
      Lead.status_value(:represado),
      2.days.ago
    ])
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
    current_tenant.whatsapp_conversations.find_by(lead: lead) ||
      begin
        recipient = lead.whatsapp_recipient
        if recipient.is_a?(Hash)
          current_tenant.whatsapp_conversations.find_by(business_scoped_user_id: recipient[:user_id].to_s)
        elsif recipient.present?
          current_tenant.whatsapp_conversations.find_by(contact_phone: normalize_whatsapp_phone(recipient))
        end
      end
  end

  def find_or_create_whatsapp_conversation_for!(lead)
    recipient = lead.whatsapp_recipient
    raise ArgumentError, "Este lead não possui telefone ou BSUID para abrir conversa no WhatsApp." if recipient.blank?

    conversation = existing_whatsapp_conversation_for(lead)
    conversation = bind_whatsapp_conversation_to_lead!(conversation, lead) if conversation
    conversation ||= if recipient.is_a?(Hash)
                       current_tenant.whatsapp_conversations.find_or_initialize_by(business_scoped_user_id: recipient[:user_id].to_s)
                     else
                       current_tenant.whatsapp_conversations.find_or_initialize_by(contact_phone: normalize_whatsapp_phone(recipient))
                     end

    conversation.contact_phone ||= normalize_whatsapp_phone(recipient) unless recipient.is_a?(Hash)
    conversation.business_scoped_user_id ||= recipient[:user_id].to_s if recipient.is_a?(Hash)
    conversation.contact_name ||= lead.display_name
    conversation.lead ||= lead
    conversation.status ||= "open"
    conversation.save!
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
      return redirect_to admin_lead_path(@lead), alert: future_activity_limit_message
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
      redirect_to admin_lead_path(@lead), notice: "Retorno agendado."
    else
      redirect_to admin_lead_path(@lead), alert: task.errors.full_messages.to_sentence
    end
  end

  def schedule_visit_activity
    starts_at = params[:starts_at].presence
    unless future_activity_allowed?(starts_at)
      return redirect_to admin_lead_path(@lead), alert: future_activity_limit_message
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
      invite_via_email: ActiveModel::Type::Boolean.new.cast(params[:invite_via_email]),
      invite_via_whatsapp: ActiveModel::Type::Boolean.new.cast(params[:invite_via_whatsapp]),
      invite_email_recipients: params[:invite_email_recipients]
    )

    unless appointment.save
      return redirect_to admin_lead_path(@lead), alert: appointment.errors.full_messages.to_sentence
    end

    send_visit_invites(appointment)
    LeadActivity.log!(lead: @lead, kind: "activity_scheduled", metadata: { activity_kind: "visit", starts_at: appointment.starts_at, by: current_admin_user&.name })
    redirect_to admin_lead_path(@lead), notice: "Visita agendada."
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
    integration = WhatsappBusinessIntegration.current(current_tenant)
    @whatsapp_conversation = existing_whatsapp_conversation_for(@lead)

    if auto_open_lead_whatsapp_conversation?(integration)
      @whatsapp_conversation = @whatsapp_conversation.present? ?
        bind_whatsapp_conversation_to_lead!(@whatsapp_conversation, @lead) :
        find_or_create_whatsapp_conversation_for!(@lead)
    end

    @lead_activation_template = Whatsapp::LeadActivationTemplate.for(tenant: current_tenant, integration: integration)
    @whatsapp_templates = approved_lead_whatsapp_templates(integration)
    # 100 e nao 12: com 12 o historico (videos/audios de dias atras) sumia do painel
    @whatsapp_messages = @whatsapp_conversation ? lead_whatsapp_panel_messages(@whatsapp_conversation) : []
    snapshot = @whatsapp_conversation ? Whatsapp::ThreadContextSnapshot.new(
      conversation: @whatsapp_conversation,
      messages: @whatsapp_messages,
      focus_mode: false,
      tenant: current_tenant
    ) : nil
    @whatsapp_summary = snapshot ? snapshot.to_h.fetch(:thread_summary) : { pending_count: 0, failed_count: 0, media_count: 0, last_activity_at: nil }
    @whatsapp_thread_context_locals = snapshot ? snapshot.to_h : {}
  rescue => e
    Rails.logger.warn("[Admin::LeadsController#load_lead_whatsapp_context] lead_id=#{@lead&.id} tenant_id=#{current_tenant&.id} erro=#{e.class}: #{e.message}")
    apply_lead_whatsapp_notice!(
      "O bloco do WhatsApp não pôde ser carregado agora. O lead permanece disponível; revise pendências da integração ou da conversa.",
      detail: e.message
    )
  end

  def apply_lead_whatsapp_notice!(message, detail: nil)
    @whatsapp_conversation = nil
    @lead_activation_template = nil
    @whatsapp_templates = []
    @whatsapp_messages = []
    @whatsapp_summary = { pending_count: 0, failed_count: 0, media_count: 0, last_activity_at: nil }
    @whatsapp_thread_context_locals = {}
    @lead_whatsapp_notice = message
    @lead_whatsapp_notice_detail = detail
  end

  def approved_lead_whatsapp_templates(integration)
    templates = [@lead_activation_template]
    templates += Whatsapp::LeadConversationTemplates.names.map do |name|
      Whatsapp::LeadConversationTemplates.for(tenant: current_tenant, integration:, name:)
    end

    templates.compact.select { |template| template.persisted? && template.approved? }
  end

  def auto_open_lead_whatsapp_conversation?(integration)
    can?(:view, :whatsapp_inbox) &&
      @lead.whatsapp_recipient.present? &&
      integration.messaging_ready?
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

  # Abre o destino conforme a config (WhatsApp do lead ou tela do lead).
  def open_attended_lead(lead)
    integration = WhatsappBusinessIntegration.current(current_tenant)
    inbox_attendance = integration.present? && integration.try(:inbox_attendance_enabled?) &&
      integration.messaging_ready? && can?(:view, :whatsapp_inbox)

    if inbox_attendance && lead.whatsapp_recipient.present?
      redirect_to admin_lead_path(lead, anchor: "whatsapp")
    elsif PushSetting.instance.open_whatsapp_on_click? && lead.direct_whatsapp_url.present?
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

  # Só a permissão da ação: o recorte por registro já vem do
  # authorize_lead_access! (before_action do destroy), que garante que o lead
  # está no escopo acessível do usuário.
  def can_destroy_lead?
    tenant_owner? || can?(:delete, :leads)
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
  end

  def lead_stage_color_map
    scope = if @selected_pipeline.present?
      @selected_pipeline.stages.active.ordered
    else
      current_tenant.lead_pipeline_stages.active.ordered
    end

    visible_stages_for(scope).index_by(&:name).transform_values(&:display_color)
  end

  def load_pwa_leads_context(filtered_scope)
    @pwa_lead_tab = params[:mobile_tab].presence_in(%w[todo visits future favorites all]) || "todo"
    @pwa_queue_position = current_user_distribution_queue_position

    base_scope = filtered_scope.where(admin_user_id: current_admin_user&.id)
    @pwa_tab_counts = {
      "todo" => pwa_lead_scope_for_tab(base_scope, "todo").reorder(nil).count,
      "visits" => pwa_lead_scope_for_tab(base_scope, "visits").reorder(nil).count,
      "future" => pwa_lead_scope_for_tab(base_scope, "future").reorder(nil).count,
      "favorites" => pwa_lead_scope_for_tab(base_scope, "favorites").reorder(nil).count,
      "all" => pwa_lead_scope_for_tab(base_scope, "all").reorder(nil).count
    }

    @pwa_leads = pwa_lead_scope_for_tab(base_scope, @pwa_lead_tab)
                 .includes(:admin_user, lead_labelings: :lead_label)
                 .order(updated_at: :desc, created_at: :desc)
                 .limit(PWA_LEAD_LIST_PAGE_SIZE)
                 .to_a
    load_pwa_lead_activity_context(@pwa_leads)
  end

  def pwa_lead_scope_for_tab(base_scope, tab)
    case tab
    when "todo"
      pwa_actionable_leads(base_scope)
    when "visits"
      base_scope.where(id: pwa_future_visit_lead_ids(base_scope))
    when "future"
      base_scope.where(id: pwa_future_task_lead_ids(base_scope))
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
        priority_statuses: [Lead.status_value(:novo), Lead.status_value(:waiting_acceptance), Lead.status_value(:represado)],
        scheduled_later_ids: pwa_later_scheduled_lead_ids(base_scope)
      )
  end

  def pwa_future_visit_lead_ids(base_scope)
    appointment_ids = Appointment
      .where(tenant_id: current_tenant.id, admin_user_id: current_admin_user&.id, kind: "visita", status: "agendado")
      .upcoming
      .select(:lead_id)

    base_scope
      .where("leads.id IN (:appointment_ids) OR leads.id IN (:external_visit_ids)",
             appointment_ids: appointment_ids,
             external_visit_ids: pwa_external_schedule_lead_ids(base_scope, visits: true, timing: :upcoming))
      .select(:id)
  end

  def pwa_future_task_lead_ids(base_scope)
    task_ids = Task
      .where(tenant_id: current_tenant.id, admin_user_id: current_admin_user&.id)
      .pendentes
      .where("due_at > ?", Time.current.end_of_day)
      .select(:lead_id)

    base_scope
      .where("leads.id IN (:task_ids) OR leads.id IN (:external_task_ids)",
             task_ids: task_ids,
             external_task_ids: pwa_external_schedule_lead_ids(base_scope, visits: false, timing: :future))
      .select(:id)
  end

  def pwa_due_task_lead_ids(base_scope)
    task_ids = Task
      .where(tenant_id: current_tenant.id, admin_user_id: current_admin_user&.id)
      .pendentes
      .where("due_at IS NULL OR due_at <= ?", Time.current.end_of_day)
      .where.not(id: pwa_external_future_task_ids(base_scope))
      .select(:lead_id)

    base_scope
      .where("leads.id IN (:task_ids) OR leads.id IN (:external_task_ids)",
             task_ids: task_ids,
             external_task_ids: pwa_external_schedule_lead_ids(base_scope, visits: false, timing: :due))
      .select(:id)
  end

  def pwa_later_scheduled_lead_ids(base_scope)
    base_scope
      .where("leads.id IN (:future_task_ids) OR leads.id IN (:future_visit_ids)",
             future_task_ids: pwa_future_task_lead_ids(base_scope),
             future_visit_ids: pwa_future_visit_lead_ids(base_scope))
      .select(:id)
  end

  def pwa_external_schedule_lead_ids(base_scope, visits:, timing:)
    scope = pwa_external_schedule_scope(base_scope, visits: visits)
    scope =
      case timing
      when :future
        scope.where("#{EXTERNAL_SCHEDULE_DATE_SQL} > ?", Time.current.end_of_day)
      when :due
        scope.where("#{EXTERNAL_SCHEDULE_DATE_SQL} <= ?", Time.current.end_of_day)
      when :upcoming
        scope.where("#{EXTERNAL_SCHEDULE_DATE_SQL} >= ?", Time.current.beginning_of_day)
      else
        scope
      end
    scope.select(:lead_id)
  end

  def pwa_external_future_task_ids(base_scope)
    pwa_external_schedule_scope(base_scope, visits: false)
      .where("#{EXTERNAL_SCHEDULE_DATE_SQL} > ?", Time.current.end_of_day)
      .where("NULLIF(lead_activities.metadata ->> 'task_id', '') ~ '^[0-9]+$'")
      .select(Arel.sql("CAST(NULLIF(lead_activities.metadata ->> 'task_id', '') AS bigint)"))
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
                                   .upcoming
                                   .to_a
                                   .group_by(&:lead_id)
    pwa_external_schedule_records_for(lead_ids).each do |action|
      target = action.kind == "visita" ? @pwa_next_visits_by_lead_id : @pwa_next_tasks_by_lead_id
      target[action.lead_id] ||= []
      target[action.lead_id].reject! { |item| action.task_id.present? && item.respond_to?(:id) && item.id == action.task_id.to_i }
      target[action.lead_id] << action
      target[action.lead_id].sort_by! { |item| item.due_at || Time.zone.at(0) }
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

    DistributionRuleAgent
      .joins(:distribution_rule)
      .where(admin_user_id: current_admin_user.id, distribution_rules: { tenant_id: current_tenant.id, active: true })
      .order(Arel.sql("distribution_rule_agents.position ASC, distribution_rule_agents.id ASC"))
      .pick("distribution_rule_agents.position")
  end

  def lead_status_options_for_selected_context
    if @selected_pipeline.present?
      visible = visible_stages_for(@selected_pipeline.stages.active.ordered)
      return visible.map(&:name) if visible.any?

      return Lead.status_options(pipeline: @selected_pipeline, tenant: current_tenant)
    end

    pipeline_statuses = visible_stages_for(current_tenant.lead_pipeline_stages.active.ordered).map(&:name)
    existing_statuses = lead_scope_for_current_user.reorder(nil).distinct.pluck(:status).compact
    (pipeline_statuses + existing_statuses + Lead::LEGACY_STATUSES).compact_blank.uniq
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
    @timeline = @lead.activities.recent.limit(60)
    @tasks = @lead.tasks.includes(:admin_user).ordered.limit(50)
    @actionable_tasks = actionable_lead_tasks(@tasks)
    @next_task = @actionable_tasks.select(&:pendente?).find { |task| task.due_at.present? } ||
                 @actionable_tasks.find(&:pendente?)
    @appointments = @lead.appointments.upcoming.limit(20)
    @proposals = @lead.proposals.ordered.limit(20)
    @archive_reason_options = archive_reason_options_for(@lead)
    @funnel_statuses = Lead.status_options(pipeline: @lead.lead_pipeline || @selected_pipeline, tenant: current_tenant)
    load_lead_whatsapp_context
    @push_delivery_events = push_delivery_events_for(@lead)
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
