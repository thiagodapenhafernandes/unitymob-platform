class Admin::LandingPagesController < Admin::BaseController
  include LandingPageShowcases

  requires_permission :manage, :site_publico
  before_action :set_landing_page, only: [:edit, :update, :destroy]
  before_action :load_filter_options, only: [:new, :create, :edit, :update]
  helper_method :property_code_options_for

  def index
    @landing_pages = current_tenant.landing_pages.includes(:blocks).order(created_at: :desc).paginate(page: params[:page], per_page: 20)
    @page_title = "Páginas"
    @page_subtitle = "Monte páginas com blocos: seleção de imóveis, textos, capas e botões."
  end

  def new
    @template = LandingPages::Templates.find(params[:template])
    @landing_page = current_tenant.landing_pages.new(status: "draft")
    @template.blocks.each_with_index do |attrs, index|
      @landing_page.blocks.build(attrs.merge(position: index, tenant: current_tenant))
    end
    @page_title = "Nova Página"
  end

  # JSON = autosave do editor: só rascunho, sempre criado como rascunho e sem mudar o status.
  def create
    attrs = landing_page_params
    attrs = attrs.merge(status: "draft") if request.format.json?
    @landing_page = current_tenant.landing_pages.new(attrs)
    if @landing_page.save
      respond_to do |format|
        format.html { redirect_to after_save_path, notice: "Página criada com sucesso!" }
        format.json { render json: autosave_payload, status: :created }
      end
    else
      @template = LandingPages::Templates.find(params[:template])
      load_filter_options
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { ok: false, errors: autosave_errors }, status: :unprocessable_entity }
      end
    end
  end

  def edit
    @page_title = "Editar Página: #{@landing_page.title}"
  end

  def update
    attrs = landing_page_params
    if request.format.json?
      return render json: { ok: false, errors: ["Só rascunhos salvam sozinhos. Clique em Salvar para aplicar."] }, status: :conflict unless @landing_page.draft?

      attrs = attrs.except(:status)
    end

    if @landing_page.update(attrs)
      respond_to do |format|
        format.html { redirect_to after_save_path, notice: "Página atualizada com sucesso!" }
        format.json { render json: autosave_payload }
      end
    else
      load_filter_options
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { ok: false, errors: autosave_errors }, status: :unprocessable_entity }
      end
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

  # Mesma tela do site (blocos, CSS e tema da conta) com o que está no editor e ainda não foi salvo.
  def render_preview
    @public_tenant = current_tenant
    @preview_mode = true
    @landing_page = current_tenant.landing_pages.new(preview_page_params)
    @landing_page.slug = "previa" # só para os links da vitrine (paginação/filtros) terem um endereço
    @blocks = preview_blocks.select(&:visible?)
    @showcases = build_showcases(@blocks, habitations: current_tenant.habitations)
    render "landing_pages/blocks", layout: "public_page_preview"
  end

  private

  # Ids dos blocos por posição: o editor os grava nos cartões para o próximo autosave atualizar em vez de duplicar.
  def autosave_payload
    { ok: true, edit_url: edit_admin_landing_page_path(@landing_page), update_url: admin_landing_page_path(@landing_page),
      slug: @landing_page.slug, blocks: @landing_page.blocks.reload.map { |block| { position: block.position, id: block.id } } }
  end

  def autosave_errors
    block_errors = @landing_page.blocks.flat_map { |block| block.errors.full_messages }.uniq
    block_errors.presence || @landing_page.errors.full_messages
  end

  # "Salvar" continua no editor; "Salvar e sair" volta à lista.
  def after_save_path
    params[:continue].present? ? edit_admin_landing_page_path(@landing_page) : admin_landing_pages_path
  end

  def set_landing_page
    @landing_page = current_tenant.landing_pages.friendly.find(params[:id])
  end

  def landing_page_params
    params.require(:landing_page).permit(
      :title, :slug, :description, :content, :meta_title, :meta_description, :status, :layout_columns,
      filter_params: [:q, :search, :transaction_type, :min_bedrooms, :min_suites, :min_parking, :target_price, :min_area, :opportunity, :caracteristica_unica, :status, category: [], city: [], neighborhood: [], development: [], property_codes: [], characteristics: []],
      blocks_attributes: BLOCK_PARAMS
    )
  end

  BLOCK_PARAMS = [:id, :block_type, :position, :visible, :_destroy, :image_desktop, :image_mobile, :remove_image_desktop, :remove_image_mobile, { data: {} }].freeze

  def preview_page_params
    params.fetch(:landing_page, ActionController::Parameters.new).slice(:title, :description, :layout_columns).permit(:title, :description, :layout_columns)
  end

  # Blocos do editor, na ordem da tela. Bloco já salvo reaproveita as imagens guardadas; os novos ainda não têm imagem.
  def preview_blocks
    raw = params.fetch(:landing_page, ActionController::Parameters.new).slice(:blocks_attributes).permit(blocks_attributes: BLOCK_PARAMS)[:blocks_attributes]
    saved = params[:id].present? ? current_tenant.landing_pages.friendly.find(params[:id]).blocks.index_by { |block| block.id.to_s } : {}

    raw.to_h.values.reject { |attrs| ActiveModel::Type::Boolean.new.cast(attrs["_destroy"]) }.sort_by { |attrs| attrs["position"].to_i }.filter_map do |attrs|
      block = saved[attrs["id"].to_s] || LandingPageBlock.new(tenant: current_tenant, landing_page: @landing_page)
      block.assign_attributes(attrs.slice("block_type", "visible", "data").merge("position" => attrs["position"].to_i))
      block if block.valid?
    end
  rescue ActiveRecord::RecordNotFound
    []
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

  def option_payload(options)
    options.map { |label, value| { value:, text: label } }
  end
end
