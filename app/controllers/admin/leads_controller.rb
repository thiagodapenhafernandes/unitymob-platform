class Admin::LeadsController < Admin::BaseController
  before_action -> { check_permission!(:view, :leads) }
  before_action :set_lead, only: [:show, :update, :destroy, :log_contact]
  before_action :authorize_lead_access!, only: [:show, :update, :destroy, :log_contact]
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
      respond_to do |format|
        format.html { redirect_to admin_lead_path(@lead), notice: "Lead atualizado com sucesso." }
        format.json { render json: { id: @lead.id, status: @lead.status, badge_class: Lead.status_badge_class(@lead.status) } }
      end
    else
      respond_to do |format|
        format.html { render :show, status: :unprocessable_entity }
        format.json { render json: { errors: @lead.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @lead.destroy
    redirect_to admin_leads_path, notice: "Lead excluído com sucesso."
  end

  private

  def set_lead
    @lead = Lead.find(params[:id])
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
end
