class Admin::LeadsController < Admin::BaseController
  before_action -> { check_permission!(:view, :leads) }
  before_action :set_lead, only: [:show, :update, :destroy, :log_contact, :reprocess_interest, :simulate_interest]
  before_action :authorize_lead_access!, only: [:show, :update, :destroy, :log_contact, :reprocess_interest, :simulate_interest]
  before_action :load_origin_options, only: [:index, :show, :update]

  def index
    @q = params[:q]
    @status = params[:status]
    @origin = params[:origin]
    @view_mode = params[:view].presence_in(%w[kanban list]) || "kanban"

    lead_scope = lead_scope_for_current_user
    
    if @q.present?
      lead_scope = lead_scope.where("name ILIKE :q OR email ILIKE :q OR phone ILIKE :q OR origin ILIKE :q", q: "%#{@q}%")
    end
    
    lead_scope = lead_scope.where(status: Lead.status_value(@status)) if @status.present?
    lead_scope = lead_scope.by_origin(@origin)

    stats_scope = lead_scope.reorder(nil)
    @total_leads = stats_scope.count
    @new_leads = stats_scope.where(status: Lead.status_value("Novo")).count
    @in_service_leads = stats_scope.where(status: Lead.status_value("Em Atendimento")).count
    @unassigned_leads = stats_scope.where(admin_user_id: nil).count
    @status_counts = stats_scope.group(:status).count
    @origin_counts = lead_scope_for_current_user.reorder(nil).where.not(origin: [nil, ""]).group(:origin).count

    lead_scope = lead_scope.includes(:admin_user).order(created_at: :desc)

    @lead_statuses = if @status.present?
                        [Lead.status_value(@status)]
                      else
                        (Lead.status_options + lead_scope.reorder(nil).distinct.pluck(:status).compact).uniq
                      end
    @leads_by_status = @lead_statuses.index_with { |status| [] }
    @kanban_leads = lead_scope.to_a
    @kanban_leads.each do |lead|
      @leads_by_status[Lead.status_value(lead.status)] ||= []
      @leads_by_status[Lead.status_value(lead.status)] << lead
    end
    @lead_counts_by_status = @leads_by_status.transform_values(&:size)
    @leads = lead_scope.paginate(page: params[:page], per_page: 20)
    property_ids = (@kanban_leads + @leads.to_a).filter_map(&:property_id).uniq
    @properties_by_id = Habitation.where(id: property_ids).index_by(&:id)
    @selected_lead = @kanban_leads.first || @leads.first
    @page_title = "Gerenciar Leads"
  end

  def show
    @page_title = "Lead: #{@lead.name}"
    @property = Habitation.find_by(id: @lead.property_id)
    @lead_audit_logs = @lead.lead_audit_logs.includes(:admin_user).recent.limit(80)

    # Workspace comercial: timeline unificada + tarefas + propostas + próxima ação
    @timeline = @lead.activities.recent.limit(60)
    @tasks = @lead.tasks.includes(:admin_user).ordered.limit(50)
    @next_task = @lead.tasks.pendentes.where.not(due_at: nil).order(:due_at).first ||
                 @lead.tasks.pendentes.order(:created_at).first
    @appointments = @lead.appointments.upcoming.limit(20)
    @proposals = @lead.proposals.ordered.limit(20)
    @funnel_statuses = Lead.status_options
    load_interest_intelligence
  end

  # Destino do clique na notificação push de novo lead. Decide no momento do
  # clique (o tempo passa entre receber e tocar): se o lead ainda é do corretor
  # (dentro do prazo do pocket), aceita e abre conforme a config global; se já
  # foi redistribuído (prazo estourado), mostra a tela de tempo esgotado.
  def attend
    @lead = Lead.find_by(id: params[:id])
    return render :attend_expired, status: :ok unless @lead

    # Shark Tank: lead sem dono em "Aguardando Aceite" — corrida pra reivindicar.
    if @lead.admin_user_id.nil? && shark_tank_open?(@lead)
      claimed = Lead.claim!(@lead.id, current_admin_user&.id)
      @lead.reload
      @lead.activities.create(kind: "accepted", metadata: { by: current_admin_user&.name, shark_tank: true }.compact) if claimed

      unless @lead.admin_user_id == current_admin_user&.id
        @attend_reason = :taken
        return render :attend_expired, status: :ok
      end

      return open_attended_lead(@lead)
    end

    unless lead_still_mine?(@lead)
      return render :attend_expired, status: :ok
    end

    accept_lead!(@lead)
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

  def destroy
    @lead.destroy
    redirect_to admin_leads_path, notice: "Lead excluído com sucesso."
  end

  private

  def set_lead
    @lead = Lead.find(params[:id])
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
    if PushSetting.instance.open_whatsapp_on_click? && lead.direct_whatsapp_url.present?
      redirect_to lead.direct_whatsapp_url, allow_other_host: true
    else
      redirect_to admin_lead_path(lead)
    end
  end

  # Aceita o lead ao abrir: passa de "Aguardando Aceite" para "Em Atendimento",
  # travando o PocketExpirationJob (que só redistribui se ainda waiting_acceptance).
  def accept_lead!(lead)
    return unless Lead.status_value(lead.status) == Lead.status_value(:waiting_acceptance)

    lead.update(status: Lead.status_value(:em_atendimento))
    lead.activities.create(kind: "accepted", metadata: { by: current_admin_user&.name }.compact)
  end

  def authorize_lead_access!
    return if lead_scope_for_current_user.where(id: @lead.id).exists?
    redirect_to admin_leads_path, alert: "Você não tem acesso a este lead."
  end

  def lead_params
    permitted = [:status, :notes, :origin]
    permitted << :admin_user_id if can?(:manage, :leads) || owns_all_resource?(:leads)
    attributes = params.require(:lead).permit(permitted)

    if attributes[:admin_user_id].present? && permitted_admin_user_ids_for_leads.exclude?(attributes[:admin_user_id].to_i)
      attributes.delete(:admin_user_id)
    end

    attributes
  end

  def load_origin_options
    @origin_options = Lead.origin_options
    @status_options = Lead.status_options
    @broker_options = permitted_admin_users_for_leads.order(:name).pluck(:name, :id)
  end

  def lead_scope_for_current_user
    return Lead.none unless current_admin_user

    owner_ids = visible_owner_ids(:leads)
    return Lead.all if owner_ids.nil? # escopo "all"/admin: sem filtro de dono

    scope = Lead.where(admin_user_id: owner_ids)
    # Ao ver a equipe, mantém o recorte por tipo de atuação (venda/locação) do gestor.
    scope = filter_leads_by_acting_type(scope) if include_team?(:leads)
    scope
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
    return AdminUser.active if owns_all_resource?(:leads)

    if current_admin_user.can_view_team?(:leads)
      scope = AdminUser.active.where(id: current_admin_user.team_scope_ids)
      return filter_users_by_acting_type(scope)
    end

    AdminUser.active.where(id: current_admin_user.id)
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
    @property = Habitation.find_by(id: @lead.property_id)
    @lead_audit_logs = @lead.lead_audit_logs.includes(:admin_user).recent.limit(80)
    @timeline = @lead.activities.recent.limit(60)
    @tasks = @lead.tasks.includes(:admin_user).ordered.limit(50)
    @next_task = @lead.tasks.pendentes.where.not(due_at: nil).order(:due_at).first ||
                 @lead.tasks.pendentes.order(:created_at).first
    @appointments = @lead.appointments.upcoming.limit(20)
    @proposals = @lead.proposals.ordered.limit(20)
    @funnel_statuses = Lead.status_options
    load_origin_options
    load_interest_intelligence
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
