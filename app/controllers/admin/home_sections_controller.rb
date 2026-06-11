class Admin::HomeSectionsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :marketing) }
  before_action :set_home_section, only: [:show, :edit, :update, :destroy]
  
  def index
    @home_sections = HomeSection.ordered.includes(:home_section_items)
  end
  
  def show
  end
  
  def new
    @home_section = HomeSection.new
  end
  
  def create
    @home_section = HomeSection.new(home_section_params)
    
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
    @home_section = HomeSection.find(params[:id])
    @home_section.update(active: !@home_section.active)
    redirect_to admin_home_sections_path, notice: "Seção #{@home_section.active? ? 'ativada' : 'desativada'} com sucesso!"
  end
  
  def update_order
    params[:order].each_with_index do |id, index|
      HomeSection.find(id).update(order_position: index + 1)
    end
    head :ok
  end
  
  private
  
  def set_home_section
    @home_section = HomeSection.find(params[:id])
  end
  
  def home_section_params
    permitted = params.require(:home_section).permit(
      :section_type,
      :title,
      :subtitle,
      :active,
      :display_order,
      :order_position,
      property_filters: HomeSection::PROPERTY_FILTER_OPTIONS.keys
    )
    filters = permitted.delete(:property_filters)
    filters = if filters.respond_to?(:to_unsafe_h)
                filters.to_unsafe_h
              elsif filters.respond_to?(:to_h)
                filters.to_h
              else
                {}
              end
    permitted.to_h.merge(property_filters: filters)
  end
end
