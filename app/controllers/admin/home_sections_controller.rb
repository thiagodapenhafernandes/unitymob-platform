class Admin::HomeSectionsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :marketing) }
  before_action :set_home_section, only: [:show, :edit, :update, :destroy]
  before_action :set_property_options, only: [:new, :edit, :create, :update]
  
  def index
    @home_sections = current_tenant.home_sections.ordered.includes(:home_section_items)
  end
  
  def show
  end
  
  def new
    @home_section = current_tenant.home_sections.new(section_type: "featured_properties")
  end
  
  def create
    @home_section = current_tenant.home_sections.new(home_section_params)
    
    if @home_section.save
      redirect_to admin_home_sections_path, notice: 'Seção criada com sucesso!'
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
  end
  
  def update
    if @home_section.update(home_section_params)
      redirect_to admin_home_sections_path, notice: 'Seção atualizada com sucesso!'
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    @home_section.destroy
    redirect_to admin_home_sections_path, notice: 'Seção removida com sucesso!'
  end
  
  def toggle_active
    @home_section = current_tenant.home_sections.find(params[:id])
    @home_section.update(active: !@home_section.active)
    redirect_to admin_home_sections_path, notice: "Seção #{@home_section.active? ? 'ativada' : 'desativada'} com sucesso!"
  end
  
  def update_order
    params[:order].each_with_index do |id, index|
      current_tenant.home_sections.find(id).update(order_position: index + 1)
    end
    head :ok
  end
  
  private
  
  def set_home_section
    @home_section = current_tenant.home_sections.find(params[:id])
  end
  
  def home_section_params
    permitted = params.require(:home_section).permit(
      :title,
      :subtitle,
      :active,
      property_filters: [
        *HomeSection::PROPERTY_FILTER_OPTIONS.keys,
        { selected_property_ids: [] }
      ]
    )
    filters = permitted.delete(:property_filters)
    filters = if filters.respond_to?(:to_unsafe_h)
                filters.to_unsafe_h
              elsif filters.respond_to?(:to_h)
                filters.to_h
              else
                {}
    end
    filters["selected_property_ids"] = permitted_property_ids(filters["selected_property_ids"])
    attrs = permitted.to_h.merge(property_filters: filters)
    attrs[:section_type] = HomeSection.infer_section_type_from_filters(filters, fallback: section_type_fallback)
    attrs[:order_position] = next_order_position unless @home_section&.persisted?
    attrs
  end

  def section_type_fallback
    current_type = @home_section&.section_type
    return if current_type.in?(HomeSection::PROPERTY_SECTION_TYPES)

    current_type
  end

  def next_order_position
    current_tenant.home_sections.maximum(:order_position).to_i + 1
  end

  def permitted_property_ids(values)
    requested_ids = Array(values)
      .flat_map { |value| value.to_s.split(/[,\s]+/) }
      .filter_map { |value| Integer(value, exception: false) }
      .select(&:positive?)
      .uniq
    return [] if requested_ids.empty?

    available_ids = current_tenant.habitations.where(id: requested_ids).reorder(nil).pluck(:id).map(&:to_i)
    requested_ids & available_ids
  end

  def set_property_options
    selected_ids = params.dig(:home_section, :property_filters, :selected_property_ids).presence || @home_section&.selected_property_ids
    selected_ids = Array(selected_ids).map(&:to_i).select(&:positive?)

    scope = current_tenant.habitations.includes(:address)

    selected_records = selected_ids.any? ? scope.where(id: selected_ids) : Habitation.none
    recent_records = current_tenant
      .habitations
      .active
      .includes(:address)
      .where.not(id: selected_ids)
      .newest_first
      .limit(1_500)

    records = (selected_records.to_a + recent_records.to_a).uniq(&:id)
    @property_options = records.map { |habitation| [property_option_label(habitation), habitation.id] }
  end

  def property_option_label(habitation)
    location = [habitation.address&.bairro, habitation.address&.cidade].compact_blank.join(" - ")
    title = habitation.titulo_anuncio.presence || habitation.nome_empreendimento.presence || habitation.categoria.presence || "Imóvel"
    code = habitation.codigo.presence || habitation.id

    ["##{code}", title, location.presence].compact_blank.join(" · ")
  end
end
