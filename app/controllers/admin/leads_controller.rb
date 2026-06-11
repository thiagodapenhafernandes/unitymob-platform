class Admin::LeadsController < Admin::BaseController
  before_action -> { check_permission!(:view, :leads) }
  before_action :set_lead, only: [:show, :update, :destroy]
  before_action :authorize_lead_access!, only: [:show, :update, :destroy]
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
    @properties_by_id = Habitation.where(id: @kanban_leads.filter_map(&:property_id).uniq).index_by(&:id)
    @leads = lead_scope.paginate(page: params[:page], per_page: 20)
    @page_title = "Gerenciar Leads"
  end

  def show
    @page_title = "Lead: #{@lead.name}"
    @property = Habitation.find_by(id: @lead.property_id)
    @lead_audit_logs = @lead.lead_audit_logs.includes(:admin_user).recent.limit(80)
  end

  def update
    if @lead.update(lead_params)
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
    return Lead.all if current_admin_user.admin?
    return manager_lead_scope if current_admin_user.profile&.manager? && owns_all_resource?(:leads)
    return Lead.all if owns_all_resource?(:leads)

    Lead.where(admin_user_id: current_admin_user.id)
  end

  def manager_lead_scope
    case current_admin_user.acting_type
    when "sales"
      Lead.joins(:admin_user).where(admin_users: { acting_type: %i[sales both] })
    when "rentals"
      Lead.joins(:admin_user).where(admin_users: { acting_type: %i[rentals both] })
    else
      Lead.all
    end
  end

  def permitted_admin_users_for_leads
    return AdminUser.none unless current_admin_user
    return AdminUser.active if current_admin_user.admin?
    return manager_team_users if current_admin_user.profile&.manager? && owns_all_resource?(:leads)
    return AdminUser.active if owns_all_resource?(:leads)

    AdminUser.active.where(id: current_admin_user.id)
  end

  def manager_team_users
    case current_admin_user.acting_type
    when "sales"
      AdminUser.active.where(acting_type: %i[sales both])
    when "rentals"
      AdminUser.active.where(acting_type: %i[rentals both])
    else
      AdminUser.active
    end
  end

  def permitted_admin_user_ids_for_leads
    permitted_admin_users_for_leads.pluck(:id)
  end
end
