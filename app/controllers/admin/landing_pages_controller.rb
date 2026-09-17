class Admin::LandingPagesController < Admin::BaseController
  requires_permission :manage, :site_publico
  before_action :set_landing_page, only: [:edit, :update, :destroy]
  before_action :load_filter_options, only: [:new, :create, :edit, :update]

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
      load_filter_options
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
      load_filter_options
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
      items: preview_items(habitations_scope),
      metrics: {
        avg_price: view_context.number_to_currency(avg_price_cents / 100.0),
        min_price: view_context.number_to_currency(min_price_cents / 100.0),
        max_price: view_context.number_to_currency(max_price_cents / 100.0),
        distribution: distribution
      }
    }
  rescue StandardError => e
    logger.error "[LandingPagePreview] tenant_id=#{current_tenant.id} error=#{e.class.name}"
    render json: { count: 0, items: [], metrics: { avg_price: "R$ 0,00", min_price: "R$ 0,00", max_price: "R$ 0,00", distribution: {} } }
  end

  def filter_options
    render json: landing_page_filter_options
  end

  private

  def set_landing_page
    @landing_page = current_tenant.landing_pages.friendly.find(params[:id])
  end

  def landing_page_params
    params.require(:landing_page).permit(
      :title, :slug, :description, :content, :meta_title, :meta_description, :active, 
      filter_params: [:q, :search, :transaction_type, :min_bedrooms, :min_suites, :min_parking, :target_price, :min_area, :opportunity, :caracteristica_unica, :status, category: [], city: [], neighborhood: [], development: [], property_codes: [], characteristics: []]
    )
  end

  def preview_params
    params.permit(
      :q, :search, :transaction_type, :min_bedrooms, :min_suites, :min_parking, :target_price, :min_area, :opportunity, :caracteristica_unica, :status,
      category: [], city: [], neighborhood: [], development: [], property_codes: [], characteristics: []
    )
  end

  def preview_items(scope)
    scope.unscope(:order).includes(:address).order(updated_at: :desc).limit(8).map do |habitation|
      {
        code: habitation.codigo.to_s,
        title: habitation.display_title,
        development: habitation.nome_empreendimento.to_s.presence,
        location: [habitation.public_neighborhood, habitation.cidade].compact_blank.join(" - "),
        price: preview_price_label(habitation)
      }
    end
  end

  def preview_price_label(habitation)
    if habitation.valor_venda_cents.to_i.positive?
      view_context.number_to_currency(habitation.valor_venda_cents.to_i / 100.0)
    elsif habitation.valor_locacao_cents.to_i.positive?
      "#{view_context.number_to_currency(habitation.valor_locacao_cents.to_i / 100.0)}/mês"
    else
      "Sob consulta"
    end
  end

  def load_filter_options
    scope = current_tenant.habitations.active.left_outer_joins(:address)
    @property_categories = scope.distinct.pluck(:categoria).compact.sort
    @property_cities = scope.distinct.pluck(Arel.sql("COALESCE(addresses.cidade, habitations.cidade)")).compact.sort
    @property_neighborhoods = scope.distinct.pluck(Arel.sql("COALESCE(addresses.bairro, habitations.bairro)")).compact.uniq.sort
    @selected_property_code_options = property_code_options_for(selected_filter_values("property_codes"), exact: true)
    @selected_development_options = selected_filter_values("development").map { |name| [name, name] }
  end

  def landing_page_filter_options
    term = params[:q].to_s.strip
    return [] if term.length < 2

    case params[:type].to_s
    when "property_codes"
      option_payload(property_code_options_for(term))
    when "developments"
      option_payload(development_options_for(term))
    else
      []
    end
  end

  def property_code_options_for(value, exact: false)
    values = Array(value).compact_blank.map(&:to_s)
    scope = current_tenant.habitations.active

    if !exact && values.one? && values.first.length >= 2
      term = "%#{ActiveRecord::Base.sanitize_sql_like(values.first)}%"
      scope = scope.where(
        "habitations.codigo ILIKE :term OR unaccent(habitations.titulo_anuncio) ILIKE unaccent(:term) OR unaccent(habitations.nome_empreendimento) ILIKE unaccent(:term)",
        term:
      )
    elsif values.any?
      scope = scope.where(codigo: values)
    else
      return []
    end

    scope.order(Arel.sql("habitations.codigo ASC NULLS LAST")).limit(30).map do |habitation|
      [property_code_option_label(habitation), habitation.codigo.to_s]
    end
  end

  def development_options_for(term)
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
    current_tenant.habitations.active
      .where("nome_empreendimento IS NOT NULL AND nome_empreendimento <> ''")
      .where("unaccent(nome_empreendimento) ILIKE unaccent(?)", pattern)
      .distinct
      .order(:nome_empreendimento)
      .limit(30)
      .pluck(:nome_empreendimento)
      .compact_blank
      .uniq
      .map { |name| [name, name] }
  end

  def property_code_option_label(habitation)
    ["##{habitation.codigo}", habitation.display_title, habitation.nome_empreendimento].compact_blank.join(" · ")
  end

  def selected_filter_values(key)
    Array(@landing_page&.filter_params&.[](key)).compact_blank.map(&:to_s)
  end

  def option_payload(options)
    options.map { |label, value| { value:, text: label } }
  end
end
