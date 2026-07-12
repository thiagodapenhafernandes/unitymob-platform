class Admin::LandingPagesController < Admin::BaseController
  before_action -> { check_permission!(:manage, :marketing) }
  before_action :set_landing_page, only: [:edit, :update, :destroy]

  def index
    @landing_pages = current_tenant.landing_pages.order(created_at: :desc).paginate(page: params[:page], per_page: 20)
    @page_title = "Páginas SEO e Dinâmicas"
    @page_subtitle = "Gerencie páginas de busca personalizada e otimização para o Google."
  end

  def new
    @landing_page = current_tenant.landing_pages.new
    @page_title = "Nova Página"
  end

  def create
    @landing_page = current_tenant.landing_pages.new(landing_page_params)
    if @landing_page.save
      redirect_to admin_landing_pages_path, notice: "Página criada com sucesso!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @page_title = "Editar Página: #{@landing_page.title}"
  end

  def update
    if @landing_page.update(landing_page_params)
      redirect_to admin_landing_pages_path, notice: "Página atualizada com sucesso!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @landing_page.destroy
    redirect_to admin_landing_pages_path, notice: "Página excluída com sucesso!"
  end

  def preview
    habitations_scope = current_tenant.habitations.active.advanced_search(preview_params)
    
    total_count = habitations_scope.count
    
    if total_count > 0
      prices_scope = habitations_scope.where("valor_venda_cents > 0")
      
      avg_price_cents = prices_scope.average(:valor_venda_cents) || 0
      min_price_cents = prices_scope.minimum(:valor_venda_cents) || 0
      max_price_cents = prices_scope.maximum(:valor_venda_cents) || 0
      
      distribution_hash = habitations_scope.unscope(:order).group(:categoria).count
      distribution = distribution_hash.sort_by { |_, v| -v }.first(5).to_h
    else
      avg_price_cents = min_price_cents = max_price_cents = 0
      distribution = {}
    end

    render json: {
      count: total_count,
      metrics: {
        avg_price: view_context.number_to_currency(avg_price_cents / 100.0),
        min_price: view_context.number_to_currency(min_price_cents / 100.0),
        max_price: view_context.number_to_currency(max_price_cents / 100.0),
        distribution: distribution
      }
    }
  rescue => e
    logger.error "Preview Dashboard Error: #{e.message}"
    render json: { count: 0, metrics: { avg_price: "R$ 0,00", min_price: "R$ 0,00", max_price: "R$ 0,00", distribution: {} } }
  end

  private

  def set_landing_page
    @landing_page = current_tenant.landing_pages.friendly.find(params[:id])
  end

  def landing_page_params
    params.require(:landing_page).permit(
      :title, :slug, :description, :content, :meta_title, :meta_description, :active, 
      filter_params: [:transaction_type, :min_bedrooms, :min_suites, :min_parking, :target_price, :min_area, :opportunity, :caracteristica_unica, :status, category: [], city: [], neighborhood: [], characteristics: []]
    )
  end

  def preview_params
    params.permit(
      :transaction_type, :min_bedrooms, :min_suites, :min_parking, :target_price, :min_area, :opportunity, :caracteristica_unica, :status,
      category: [], city: [], neighborhood: [], characteristics: []
    )
  end
end
