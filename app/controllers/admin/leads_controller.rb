class Admin::LeadsController < Admin::BaseController
  # Kanban nunca renderiza mais que isso por coluna (paginação continua na lista).
  KANBAN_COLUMN_LIMIT = 75

  before_action -> { check_permission!(:view, :leads) }
  before_action :set_lead, only: [:show, :update, :destroy, :log_contact, :reprocess_interest, :simulate_interest, :open_whatsapp_conversation, :activate_whatsapp_template]
  before_action :authorize_lead_access!, only: [:show, :update, :destroy, :log_contact, :reprocess_interest, :simulate_interest, :open_whatsapp_conversation, :activate_whatsapp_template]
  before_action :load_origin_options, only: [:index, :show, :update]

  def index
    @q = params[:q]
    @status = params[:status]
    @origin = params[:origin]
    @tags = Array(params[:tags]).map(&:to_s).reject(&:blank?)
    @broker_id = params[:broker_id]
    @property_filter = params[:property_filter]
    @property_q = params[:property_q].to_s.strip
    @contact_filter = params[:contact_filter]
    @start_date = params[:start_date]
    @end_date = params[:end_date]
    @view_mode = resolve_view_mode

    lead_scope = lead_scope_for_current_user
    
    if @q.present?
      term = "%#{ActiveRecord::Base.sanitize_sql_like(@q.to_s.strip)}%"
      lead_scope = lead_scope.where(
        "leads.name ILIKE :q OR leads.email ILIKE :q OR leads.phone ILIKE :q OR leads.client_name ILIKE :q OR leads.client_email ILIKE :q OR leads.client_phone ILIKE :q OR leads.origin ILIKE :q OR leads.product ILIKE :q",
        q: term
      )
    end
    
    lead_scope = lead_scope.where(leads: { status: Lead.status_value(@status) }) if @status.present?
    lead_scope = lead_scope.by_origin(@origin)
    lead_scope = lead_scope.with_any_tags(@tags)
    lead_scope = apply_broker_filter(lead_scope)
    lead_scope = apply_property_filter(lead_scope)
    lead_scope = apply_contact_filter(lead_scope)
    lead_scope = apply_created_at_filter(lead_scope)

    stats_scope = lead_scope.reorder(nil)
    @total_leads = stats_scope.count
    @new_leads = stats_scope.where(status: Lead.status_value("Novo")).count
    @in_service_leads = stats_scope.where(status: Lead.status_value("Em Atendimento")).count
    @unassigned_leads = stats_scope.where(admin_user_id: nil).count
    @status_counts = stats_scope.group(:status).count
    @origin_counts = lead_scope_for_current_user.reorder(nil).where.not(origin: [nil, ""]).group(:origin).count

    lead_scope = lead_scope.includes(:admin_user, lead_labelings: :lead_label).order(created_at: :desc)

    @lead_statuses = if @status.present?
                        [Lead.status_value(@status)]
                      else
                        (Lead.status_options + lead_scope.reorder(nil).distinct.pluck(:status).compact).uniq
                      end
    @leads_by_status = @lead_statuses.index_with { |status| [] }
    # Teto por coluna DIRETO NO BANCO (janela por status): antes carregava a
    # base inteira de leads na memória a cada visita ao kanban.
    ranked = lead_scope.reorder(nil).select(
      "leads.*, ROW_NUMBER() OVER (PARTITION BY leads.status ORDER BY leads.created_at DESC) AS kanban_rank"
    )
    @kanban_leads = Lead.from(ranked, :leads)
                        .where("kanban_rank <= ?", KANBAN_COLUMN_LIMIT)
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
    @kanban_column_limit = KANBAN_COLUMN_LIMIT
    @leads = lead_scope.paginate(page: params[:page], per_page: 20)
    property_ids = (@kanban_leads + @leads.to_a).filter_map(&:property_id).uniq
    @properties_by_id = current_tenant.habitations.where(id: property_ids).index_by(&:id)
    @selected_lead = @kanban_leads.first || @leads.first
    @page_title = "Gerenciar Leads"
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
    @funnel_statuses = Lead.status_options
    load_lead_whatsapp_context
    @push_delivery_events = push_delivery_events_for(@lead)
    load_interest_intelligence
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

  def log_contact
    kind = params[:contact_kind].presence || "note"
    body = params[:body].to_s.strip
    LeadActivity.log!(lead: @lead, kind: "note", metadata: { contact_kind: kind, body: body, by: current_admin_user&.name }.compact)
    redirect_to admin_lead_path(@lead), notice: "Contato registrado."
  end

  def update
    previous_status = @lead.status
    if @lead.update(lead_params)
      if @lead.saved_change_to_status?
        LeadActivity.log!(lead: @lead, kind: "status_change", metadata: { from: previous_status, to: @lead.status, by: current_admin_user&.name })
      end
      if @lead.saved_change_to_admin_user_id? && @lead.admin_user_id.present?
        Leads::NotificationDispatcher.notify_reassignment(@lead, @lead.admin_user)
      end
      respond_to do |format|
        format.html { redirect_to admin_lead_path(@lead), notice: "Lead atualizado com sucesso." }
        format.json { render json: { id: @lead.id, status: @lead.status, badge_class: Lead.status_badge_class(@lead.status) } }
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
    unless can?(:manage, :leads) || can?(:manage, :comercial) || owns_all_resource?(:leads)
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
    @interest_simulation = true
    render :show
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

    template = current_tenant.whatsapp_templates.approved.find_by(id: params[:whatsapp_template_id])
    return redirect_to(return_path || admin_lead_path(@lead), alert: "Selecione um template aprovado.") unless template

    conversation = find_or_create_whatsapp_conversation_for!(@lead)
    message = conversation.messages.create!(
      direction: "outbound",
      status: "pending",
      msg_type: "template",
      template_name: template.name,
      body: template.body,
      admin_user: current_admin_user
    )
    conversation.touch_last_message!(message)
    Whatsapp::SendMessageJob.dispatch(message.id, tenant_id: message.tenant_id)
    LeadActivity.log!(lead: @lead, kind: "whatsapp_out", metadata: { body: message.preview, by: current_admin_user&.name })

    redirect_to(return_path || admin_whatsapp_conversation_path(conversation), notice: "Template enviado e conversa ativada no inbox.")
  rescue ArgumentError => e
    redirect_to(return_path || admin_lead_path(@lead), alert: e.message)
  end

  def destroy
    @lead.destroy
    redirect_to admin_leads_path, notice: "Lead excluído com sucesso."
  end

  private

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

  def apply_created_at_filter(scope)
    if parsed_start_date.present?
      scope = scope.where("leads.created_at >= ?", parsed_start_date.beginning_of_day)
    end

    if parsed_end_date.present?
      scope = scope.where("leads.created_at <= ?", parsed_end_date.end_of_day)
    end

    scope
  end

  def parsed_start_date
    @parsed_start_date ||= parse_filter_date(@start_date)
  end

  def parsed_end_date
    @parsed_end_date ||= parse_filter_date(@end_date)
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

  def normalize_whatsapp_phone(value)
    digits = value.to_s.gsub(/\D/, "")
    return "" if digits.blank?

    digits.length <= 11 ? "55#{digits}" : digits
  end

  def load_lead_whatsapp_context
    @whatsapp_conversation = existing_whatsapp_conversation_for(@lead)
    @whatsapp_templates = current_tenant.whatsapp_templates.approved.ordered.limit(50)
    # 100 e nao 12: com 12 o historico (videos/audios de dias atras) sumia do painel
    @whatsapp_messages = @whatsapp_conversation ? @whatsapp_conversation.messages.visible.ordered.last(100) : []
    snapshot = @whatsapp_conversation ? Whatsapp::ThreadContextSnapshot.new(
      conversation: @whatsapp_conversation,
      messages: @whatsapp_messages,
      focus_mode: false,
      tenant: current_tenant
    ) : nil
    @whatsapp_summary = snapshot ? snapshot.to_h.fetch(:thread_summary) : { pending_count: 0, failed_count: 0, media_count: 0, last_activity_at: nil }
    @whatsapp_thread_context_locals = snapshot ? snapshot.to_h : {}
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

  def lead_params
    permitted = [:status, :notes]
    # Reatribuir corretor: só gestores (escopo team/all em Leads); corretor
    # com escopo "own" edita o lead, mas não troca o dono.
    permitted << :admin_user_id if can?(:manage, :leads) && current_admin_user.scope_for(:leads) != "own"
    attributes = params.require(:lead).permit(permitted)

    if attributes[:admin_user_id].present? && permitted_admin_user_ids_for_leads.exclude?(attributes[:admin_user_id].to_i)
      attributes.delete(:admin_user_id)
    end

    attributes
  end

  def load_origin_options
    option_scope = lead_scope_for_current_user.reorder(nil)
    @origin_options = Lead.origin_options(scope: option_scope, tenant: current_tenant)
    @tag_options = Lead.tag_options(scope: option_scope)
    @status_options = Lead.status_options
    @broker_options = permitted_admin_users_for_leads.order(:name).pluck(:name, :id)
  end

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
    @funnel_statuses = Lead.status_options
    load_lead_whatsapp_context
    @push_delivery_events = push_delivery_events_for(@lead)
    load_origin_options
    load_interest_intelligence
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
