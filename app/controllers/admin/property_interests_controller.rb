class Admin::PropertyInterestsController < Admin::BaseController
  before_action -> { check_permission!(:view, :leads) }
  before_action :set_lead

  # Autocomplete de imóveis para o vínculo de interesse. REUSA a busca textual
  # do catálogo (Habitation.admin_search_text) — mesma query do índice admin.
  def search
    query = params[:q].to_s.strip
    habitations = if query.present?
      current_tenant.habitations.admin_search_text(query).limit(20)
    else
      current_tenant.habitations.none
    end

    render json: habitations.map { |habitation| { value: habitation.id, text: property_interest_option_label(habitation) } }
  end

  def create
    habitation = current_tenant.habitations.find_by(id: params.dig(:property_interest, :habitation_id) || params[:habitation_id])
    return render json: { error: "Imóvel não encontrado." }, status: :not_found unless habitation

    interest = @lead.property_interests.find_or_initialize_by(habitation: habitation)
    interest.tenant ||= current_tenant

    if interest.persisted? || interest.save
      render json: state_payload
    else
      render json: { error: interest.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  def destroy
    interest = @lead.property_interests.find_by(id: params[:id])
    interest&.destroy
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

  def property_interest_option_label(habitation)
    location = [habitation.bairro, habitation.cidade].compact_blank.join(", ")
    [habitation.codigo, habitation.display_title.presence, location.presence].compact_blank.join(" · ")
  end

  def state_payload
    {
      chips_html: render_to_string(
        partial: "admin/whatsapp_inbox/thread_property_interest_chips",
        formats: [:html],
        locals: { lead: @lead }
      )
    }
  end
end
