class Admin::HomeSectionItemsController < Admin::BaseController
  before_action -> { check_permission!(:manage, :marketing) }
  before_action :set_home_section
  before_action :set_home_section_item, only: [:edit, :update, :destroy]
  
  def new
    @home_section_item = @home_section.home_section_items.build
  end
  
  def create
    @home_section_item = @home_section.home_section_items.build(home_section_item_params)
    
    if @home_section_item.save
      redirect_to admin_home_section_path(@home_section), notice: 'Item criado com sucesso!'
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
  end
  
  def update
    if @home_section_item.update(home_section_item_params)
      redirect_to admin_home_section_path(@home_section), notice: 'Item atualizado com sucesso!'
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    @home_section_item.destroy
    redirect_to admin_home_section_path(@home_section), notice: 'Item removido com sucesso!'
  end
  
  private
  
  def set_home_section
    @home_section = current_tenant.home_sections.find(params[:home_section_id])
  end
  
  def set_home_section_item
    @home_section_item = @home_section.home_section_items.find(params[:id])
  end
  
  def home_section_item_params
    params.require(:home_section_item).permit(
      :title,
      :description,
      :active,
      :display_order,
      :icon
    )
  end
end
