class Admin::LeadLabelsController < Admin::BaseController
  before_action -> { check_permission!(:view, :leads) }
  before_action :set_lead
  before_action :set_label, only: [:update, :destroy, :toggle]

  # Abre o gerenciador de etiquetas para um lead (semeia os defaults do
  # corretor no primeiro uso). Retorna o HTML do modal.
  def index
    ensure_defaults
    render json: state_payload
  end

  def create
    label = current_admin_user.lead_labels.new(label_params.merge(tenant: current_tenant))
    if label.save
      render json: state_payload
    else
      render json: { error: label.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  def update
    if @label.update(label_params)
      render json: state_payload
    else
      render json: { error: @label.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  def destroy
    @label.destroy
    render json: state_payload
  end

  # Marca/desmarca a etiqueta no lead atual.
  def toggle
    labeling = @lead.lead_labelings.find_by(lead_label_id: @label.id)
    if labeling
      labeling.destroy
    else
      @lead.lead_labelings.create!(lead_label: @label, tenant: current_tenant)
    end
    render json: state_payload
  end

  private

  # Corretor só acessa leads DELE (escopo own/team via accessible_owner_ids);
  # gestor com escopo total (nil) acessa todos os do tenant.
  def set_lead
    scope = current_tenant.leads
    owner_ids = accessible_owner_ids(:leads)
    scope = scope.where(admin_user_id: owner_ids) unless owner_ids.nil?

    @lead = scope.find_by(id: params[:lead_id])
    return if @lead

    render json: { error: "lead_unavailable" }, status: :not_found
  end

  # Etiquetas são privadas: só encontra as do próprio corretor.
  def set_label
    @label = current_admin_user.lead_labels.find_by(id: params[:id])
    render json: { error: "not_found" }, status: :not_found unless @label
  end

  def ensure_defaults
    LeadLabel.ensure_defaults_for(current_admin_user)
  end

  def label_params
    params.require(:lead_label).permit(:name, :color)
  end

  def labels
    current_admin_user.lead_labels.ordered
  end

  def assigned_ids
    @lead.labels_for(current_admin_user).pluck(:id)
  end

  def state_payload
    {
      manager_html: render_to_string(
        partial: "admin/lead_labels/manager",
        formats: [:html],
        locals: { lead: @lead, labels: labels, assigned_ids: assigned_ids }
      ),
      chips_html: render_to_string(
        partial: "admin/lead_labels/chips",
        formats: [:html],
        locals: { lead: @lead, labels: @lead.labels_for(current_admin_user) }
      )
    }
  end
end
