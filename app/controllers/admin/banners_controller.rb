class Admin::BannersController < Admin::BaseController
  before_action -> { check_permission!(:manage, :marketing) }
  before_action :set_banner, only: [:show, :edit, :update, :destroy]
  
  def index
    @banners = current_tenant.banners.ordered.page(params[:page]).per_page(20)
  end
  
  def show
  end
  
  def new
    @banner = current_tenant.banners.new
  end
  
  def create
    @banner = current_tenant.banners.new(banner_params)
    
    if @banner.save
      redirect_to admin_banners_path, notice: 'Banner criado com sucesso!'
    else
      render :new, status: :unprocessable_entity
    end
  end
  
  def edit
  end
  
  def update
    if @banner.update(banner_params)
      redirect_to admin_banners_path, notice: 'Banner atualizado com sucesso!'
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def destroy
    @banner.destroy
    redirect_to admin_banners_path, notice: 'Banner removido com sucesso!'
  end
  
  private
  
  def set_banner
    @banner = current_tenant.banners.find(params[:id])
  end
  
  def banner_params
    params.require(:banner).permit(
      :title,
      :description,
      :link_url,
      :link_text,
      :display_order,
      :active,
      :image_desktop,
      :image_mobile,
      positions: []
    )
  end
end
