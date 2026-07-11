class HabitationsController < ApplicationController
  PUBLIC_LISTING_PER_PAGE = 12
  MAX_PUBLIC_LISTING_PAGE = ENV.fetch("PUBLIC_LISTING_MAX_PAGE", 50).to_i

  include HabitationCaching
  include ActionView::Helpers::NumberHelper
  before_action :set_habitation, only: [:show, :schedule_visit]
  before_action :redirect_to_canonical_habitation_url, only: [:show]
  before_action :authenticate_admin_user!, only: [:share_link]
  before_action :set_shareable_habitation, only: [:share_link]
  
  # GET /habitations
  # GET /imoveis
  def index
    apply_strategic_landing_params
    return if reject_invalid_public_listing_page!

    # Handle Target Price (Approximate Search ±20%)
    if params[:target_price].present?
      # Remove non-digits to get raw integer value
      target_value = params[:target_price].to_s.gsub(/\D/, '').to_i
      
      if target_value > 0
        min_price = (target_value * 0.8).to_i
        max_price = (target_value * 1.2).to_i
        
        # Merge calculated range into params for advanced_search
        params[:min_price] = min_price
        params[:max_price] = max_price
      end
    end

    filter_params = search_params
    listing_scope = public_habitation_scope
      .public_property_search(filter_params)

    total_entries = cached_listing_total_entries(listing_scope, filter_params)
    return if reject_public_listing_page_beyond_total!(total_entries)

    load_filter_options

    @habitations = listing_scope
      .includes(
        :address,
        { constructor: { logo_attachment: :blob } },
        { empreendimento: { constructor: { logo_attachment: :blob } } }
      )
      .paginate(page: requested_public_listing_page, per_page: PUBLIC_LISTING_PER_PAGE, total_entries: total_entries)
    PublicSite::CardPhotoPreloader.new(@habitations.to_a, limit: 5).call
    
    # SEO page name
    @page_name = 'imoveis'
    @discounted_results_present = discounted_results_present?
    
    # Definir meta tags para SEO
    @page_title = build_index_title
    @page_description = build_index_description
    @page_keywords = build_index_keywords
    if @strategic_landing.present?
      @page_title = "#{@strategic_landing[:title]} | #{public_site_name}"
      @page_description = @strategic_landing[:description]
      @page_keywords = [@strategic_landing[:label], "imóveis", "Balneário Camboriú", public_site_name].join(", ")
    end
    
    # Cache da página
    cache_index_page
    
    respond_to do |format|
      format.html
      format.json { render json: @habitations.map(&:card_data) }
    end
  end
  
  # GET /buscar-codigo?code=1234
  def search_by_code
    code = params[:code].to_s.strip
    
    if code.blank?
      redirect_to root_path, alert: 'Por favor, informe um código válido.'
      return
    end
    
    property = public_tenant.habitations.find_by(codigo: code)
    
    if property&.publicly_viewable?
      redirect_to habitation_path(property), notice: "Imóvel ##{code} encontrado!"
    else
      redirect_to habitations_path(search: code), 
                  alert: "Imóvel com código #{code} não encontrado. Veja outros imóveis disponíveis."
    end
  end

  # A lista é mantida no navegador para visitantes públicos, sem exigir conta.
  def favorites
    @page_title = "Imóveis favoritos | #{public_site_name}"
    @page_description = "Consulte os imóveis que você salvou para revisar depois."
  end
  
  # POST /imoveis/:id/schedule_visit
  def schedule_visit
    webhook_data = visit_params.to_h
    webhook_data["phone"] = Phones::Normalizer.call(webhook_data["phone"]).to_s if webhook_data["phone"].present?

    # Enviar webhook com dados do formulário + código do imóvel
    webhook_data = webhook_data.merge(
      property_code: @habitation.codigo,
      property_title: @habitation.display_title,
      property_url: habitation_url(@habitation)
    )
    
    WebhookService.send_form_data('property_visit_form', webhook_data, request: request)
    Seo::ConversionTracker.record!(
      event_type: "schedule_visit",
      request: request,
      habitation: @habitation,
      metadata: visit_params.to_h.slice("preferred_date", "preferred_time")
    )
    
    redirect_to habitation_path(@habitation), notice: 'Visita agendada com sucesso! Entraremos em contato para confirmar.'
  end
  
  # GET /habitations/autocomplete?q=balneario
  # GET /habitations/autocomplete?q=balneario
  def autocomplete
    term = params[:q].to_s.strip
    results = []

    if term.present?
      # 1. Cidades
      cidades = public_habitation_scope.active
                         .left_outer_joins(:address)
                         .where("unaccent(COALESCE(addresses.cidade, habitations.cidade)) ILIKE unaccent(?)", "%#{term}%")
                         .distinct
                         .limit(5)
                         .pluck(Arel.sql("COALESCE(addresses.cidade, habitations.cidade)"))
      
      results += cidades.map { |c| { label: "#{c} (Cidade)", value: c, type: 'cidade' } }

      # 2. Bairros
      bairros = public_habitation_scope.active
                          .left_outer_joins(:address)
                          .where("unaccent(COALESCE(addresses.bairro, habitations.bairro)) ILIKE unaccent(?)", "%#{term}%")
                          .distinct
                          .limit(5)
                          .pluck(Arel.sql("COALESCE(addresses.bairro, habitations.bairro)"))
      
      results += bairros.map { |b| { label: "#{b} (Bairro)", value: b, type: 'bairro' } }

      # 3. Empreendimentos
      empreendimentos = public_habitation_scope.empreendimentos_publicos
                                  .where("unaccent(nome_empreendimento) ILIKE unaccent(?)", "%#{term}%")
                                  .limit(5)
                                  .select(:nome_empreendimento, :slug)
      
      results += empreendimentos.map do |e| 
        { 
          label: "#{e.nome_empreendimento} (Empreendimento)", 
          value: e.nome_empreendimento, 
          type: 'empreendimento',
          url: habitation_path(e) # URL para redirecionamento direto
        } 
      end
    else
      # Sugestões padrão quando vazio (opcional)
      cidades_populares = public_habitation_scope.active
                                  .left_outer_joins(:address)
                                  .group(Arel.sql("COALESCE(addresses.cidade, habitations.cidade)"))
                                  .order('count_all DESC')
                                  .limit(5)
                                  .count
                                  .keys
      results += cidades_populares.map { |c| { label: c, value: c, type: 'cidade' } }
    end

    render json: results
  rescue => e
    Rails.logger.error "Autocomplete error: #{e.message}"
    render json: []
  end
  
  # GET /imoveis/:id
  def show
    unless @habitation
      redirect_to habitations_path, alert: 'Imóvel não encontrado ou indisponível no momento.'
      return
    end

    load_share_context
    @public_map = PublicMaps::PropertyPresentation.new(@habitation)

    # Incrementar contador de visualizações (em background)
    # increment_view_count(@habitation.id)
    
    property_metadata = Seo::PropertyMetadataBuilder.new(@habitation).attributes
    @page_title = property_metadata[:meta_title]
    @page_description = property_metadata[:meta_description].presence || default_property_description(@habitation)
    @page_keywords = property_metadata[:meta_keywords]
    @page_name = property_metadata[:page_name]
    @canonical_url = habitation_url(@habitation)
    
    # Image for social sharing (Open Graph)
    social_image = share_image_metadata_for(@habitation)
    @page_image = social_image[:url]
    @page_image_width = social_image[:width]
    @page_image_height = social_image[:height]
    @page_image_type = social_image[:type]
    
    # Detectar se é empreendimento e carregar unidades
    if @habitation.empreendimento?
      @is_development_page = true
      @development_units = @habitation.development_units
        .newest_first
        .includes(
          :address,
          { constructor: { logo_attachment: :blob } },
          { empreendimento: { constructor: { logo_attachment: :blob } } }
        )
        .to_a
      PublicSite::CardPhotoPreloader.new(@development_units, limit: 5).call
      # Usar template específico para empreendimentos
      render 'empreendimento_show' and return
    end
    
    # Imóveis relacionados (mesma região, quartos e faixa de preço ±20%)
    @related_properties = []
    
    if @habitation.present?
      # Calcular faixa de preço (±20%)
      base_price = @habitation.valor_venda_cents || @habitation.valor_locacao_cents
      
      if base_price && base_price > 0
        min_price = (base_price * 0.8).to_i
        max_price = (base_price * 1.2).to_i
        
        @related_properties = public_habitation_scope
          .active
          .includes(
            :address,
            { constructor: { logo_attachment: :blob } },
            { empreendimento: { constructor: { logo_attachment: :blob } } }
          )
          .left_outer_joins(:address)
          .where("COALESCE(addresses.cidade, habitations.cidade) = ?", @habitation.cidade) # Mesma cidade
          .where(dormitorios_qtd: @habitation.dormitorios_qtd)  # Mesmos quartos
          .where.not(id: @habitation.id)  # Excluir o imóvel atual
          .where(
            "(valor_venda_cents BETWEEN ? AND ?) OR (valor_locacao_cents BETWEEN ? AND ?)",
            min_price, max_price, min_price, max_price
          )
          .newest_first
          .limit(6)
          .to_a
        PublicSite::CardPhotoPreloader.new(@related_properties, limit: 5).call
      end
    end
    
    # Cache da página
    cache_show_page(@habitation)
    
    respond_to do |format|
      format.html
      format.json { render json: @habitation.card_data }
    end
  end

  def share_link
    link = HabitationShareLink.create_or_reuse_for(
      habitation: @habitation,
      admin_user: current_admin_user
    )

    render json: {
      success: true,
      url: habitation_url(@habitation, share_token: link.token),
      expires_at: link.expires_at.iso8601
    }
  rescue StandardError => e
    Rails.logger.error "[HabitationShare] erro ao gerar link: #{e.message}"
    render json: { success: false, error: "Não foi possível gerar o link de compartilhamento." }, status: :unprocessable_entity
  end
  
  private

  def set_shareable_habitation
    @habitation = find_habitation_in_scope(params[:id], current_admin_user.tenant.habitations)
    return if @habitation

    render json: { success: false, error: "Imóvel não encontrado nesta conta." }, status: :not_found
  end
  
  def set_habitation
    @habitation = find_public_habitation(params[:id])
    return if @habitation&.publicly_viewable?
    return if valid_share_token_for?(@habitation)

    reason = @habitation&.public_unavailable_reason || "nao encontrado"
    Rails.logger.info("[HabitationPublicShow] id=#{params[:id].inspect} indisponivel: #{reason}")
    redirect_to habitations_path, alert: 'Imóvel não encontrado ou indisponível no momento.'
  end

  def valid_share_token_for?(habitation)
    return false unless habitation

    token = params[:share_token].to_s.strip
    return false if token.blank?

    HabitationShareLink.active.exists?(token: token, habitation_id: habitation.id)
  end

  def find_public_habitation(identifier)
    find_habitation_in_scope(identifier, public_habitation_lookup_scope)
  end

  def find_habitation_in_scope(identifier, scope)
    identifier = identifier.to_s.strip
    return nil if identifier.blank?

    lookup_scope = scope.with_attached_photos.includes(:address)
    lookup_scope.find_by(slug: identifier) ||
      lookup_scope.find_by(codigo: identifier) ||
      find_habitation_by_trailing_code(identifier, lookup_scope) ||
      find_habitation_by_friendly_id(identifier, lookup_scope)
  end

  def public_habitation_scope
    public_tenant.habitations
  end

  def public_habitation_lookup_scope
    public_habitation_scope.with_attached_photos.includes(
      :address,
      { constructor: { logo_attachment: :blob } },
      { empreendimento: { constructor: { logo_attachment: :blob } } }
    )
  end

  def find_habitation_by_trailing_code(identifier, scope = public_habitation_lookup_scope)
    trailing_code = identifier[/(\d+)\z/, 1]
    return nil if trailing_code.blank? || trailing_code == identifier

    scope.find_by(codigo: trailing_code)
  end

  def find_habitation_by_friendly_id(identifier, scope = public_habitation_lookup_scope)
    scope.friendly.find(identifier)
  rescue ActiveRecord::RecordNotFound
    nil
  end
  
  def search_params
    permitted = params.permit(
      :page,
      :transaction_type,
      :finalidade,
      :category,
      :tipo,
      :city,
      :cidade,
      :neighborhood,
      :state,
      :min_bedrooms,
      :min_suites,
      :min_bathrooms,
      :min_parking,
      :min_area,
      :max_area,
      :min_price,
      :max_price,
      :target_price,
      :price_range,
      :furnished,
      :accepts_exchange,
      :accepts_financing,
      :search,
      :sort,
      category: [],
      city: [],
      characteristics: []
    )
    permitted.delete(:page)

    permitted[:transaction_type] = normalize_transaction_type(permitted[:transaction_type].presence || permitted[:finalidade])
    permitted[:category] = permitted[:category].presence || permitted[:tipo]
    permitted[:city] = permitted[:city].presence || permitted[:cidade]
    apply_price_range_params(permitted)

    category_values = normalize_filter_values(permitted[:category])
    permitted[:category] = category_values if category_values.any?

    city_values = normalize_filter_values(permitted[:city])
    permitted[:city] = city_values if city_values.any?

    permitted
  end

  def apply_price_range_params(permitted)
    return if permitted[:price_range].blank?

    min_price, max_price = permitted[:price_range].to_s.split("-", 2)
    permitted[:min_price] = min_price if min_price.present? && min_price.to_i.positive?
    permitted[:max_price] = max_price if max_price.present? && max_price.to_i.positive?
    permitted[:target_price] = nil
  end

  def normalize_transaction_type(value)
    case value.to_s.downcase
    when "venda", "comprar"
      "venda"
    when "aluguel", "locacao", "locação", "alugar"
      "aluguel"
    else
      value
    end
  end

  def normalize_filter_values(value)
    case value
    when Array
      value.flat_map { |item| normalize_filter_values(item) }.reject(&:blank?).uniq
    when String
      stripped = value.strip
      return [] if stripped.blank?

      if stripped.start_with?("[") && stripped.end_with?("]")
        parsed = JSON.parse(stripped) rescue nil
        return normalize_filter_values(parsed) if parsed
      end

      [stripped]
    else
      Array(value).reject(&:blank?)
    end
  end

  def load_filter_options
    @selected_categories = normalize_filter_values(params[:category])
    @selected_locations = normalize_filter_values(params[:city])

    @property_types = Rails.cache.fetch(Habitation.public_filter_property_types_cache_key(public_tenant.id), expires_in: 12.hours) do
      public_tenant.habitations.public_property_types
    end

    @location_options = Rails.cache.fetch(Habitation.public_filter_location_options_cache_key(public_tenant.id), expires_in: 6.hours) do
      public_tenant.habitations.public_location_options
    end
  end

  def requested_public_listing_page
    raw_page = params[:page].presence
    return 1 if raw_page.blank?

    raw_page = raw_page.to_s
    return nil unless raw_page.match?(/\A\d+\z/)

    raw_page.to_i
  end

  def reject_invalid_public_listing_page!
    page = requested_public_listing_page
    return false if page.present? && page.between?(1, MAX_PUBLIC_LISTING_PAGE)

    Rails.logger.info(
      "[PublicListingPageGuard] rejected invalid page=#{params[:page].inspect} " \
      "ip=#{request.remote_ip} path=#{request.fullpath}"
    )
    render plain: "Not Found", status: :not_found
    true
  end

  def reject_public_listing_page_beyond_total!(total_entries)
    page = requested_public_listing_page || 1
    total_pages = [(total_entries.to_i / PUBLIC_LISTING_PER_PAGE.to_f).ceil, 1].max
    return false if page <= total_pages

    Rails.logger.info(
      "[PublicListingPageGuard] rejected empty page=#{page} total_pages=#{total_pages} " \
      "ip=#{request.remote_ip} path=#{request.fullpath}"
    )
    render plain: "Not Found", status: :not_found
    true
  end

  def apply_strategic_landing_params
    @strategic_landing = Seo::StrategicLanding.property(params[:seo_slug])
    return if @strategic_landing.blank?

    @strategic_landing[:params].each do |key, value|
      params[key] = value
    end
  end

  def load_share_context
    return unless @habitation

    @lead_share_token = nil
    token = params[:share_token].presence
    token ||= cookies.signed[HabitationShareLink::COOKIE_KEY].presence if lgpd_consent_accepted?
    return if token.blank?

    link = HabitationShareLink.active
                              .includes(:admin_user)
                              .find_by(token: token, habitation_id: @habitation.id)
    unless link
      cookies.delete(HabitationShareLink::COOKIE_KEY)
      return
    end

    @share_link = link
    @shared_broker = link.admin_user
    @lead_share_token = link.token
    return unless lgpd_consent_accepted?

    remember_share_link(link)
    link.register_click!
    Seo::ConversionTracker.record!(
      event_type: "share_click",
      request: request,
      habitation: @habitation,
      metadata: { broker_id: link.admin_user_id }
    )
  end

  def remember_share_link(link)
    cookies.signed[HabitationShareLink::COOKIE_KEY] = {
      value: link.token,
      expires: HabitationShareLink.expiration_period.from_now,
      same_site: :lax,
      httponly: true
    }
  end
  
  def visit_params
    params.permit(:name, :email, :phone, :preferred_date, :preferred_time, :message)
  end
  
  # SEO OPTIMIZATION - Dynamic & Varied Meta Tags (Style: Conexão Imobiliária)
  def build_index_title
    count = @habitations.total_entries rescue @habitations.count
    city = location_label
    category = category_label
    
    # Determine Transaction Context
    transaction_term = case params[:transaction_type]
                       when 'venda' then 'à Venda'
                       when 'aluguel', 'locacao' then 'para Alugar'
                       else ''
                       end

    # Check for specific scenarios
    is_reduced = params[:characteristics]&.include?('opportunity') || @discounted_results_present
    
    is_luxury = params[:min_price].to_i > 2_000_000 || params[:quadra_mar] == '1' || params[:frente_mar] == '1'
    
    # Varied Templates (Randomized selection to avoid robotic patterns)
    templates = []
    
    if is_reduced
      templates << "Oportunidade: #{category} com Valor Reduzido em #{city}"
      templates << "Preço Baixo: #{category} em #{city} com Desconto"
      templates << "Ofertas de #{category} em #{city} - Aproveite"
    elsif is_luxury
      templates << "#{category} de Alto Padrão em #{city} - Exclusividade"
      templates << "Luxo e Sofisticação: #{category} em #{city}"
      templates << "Os Melhores #{category} em #{city} estão Aqui"
    else
      # Standard variations
      if transaction_term.present?
        templates << "#{category} #{transaction_term} em #{city}"
        templates << "Encontre seu #{category} #{transaction_term} em #{city}"
        templates << "Busca de #{category} #{transaction_term} na região de #{city}"
        templates << "#{category} em #{city} - Veja Opções #{transaction_term}"
      else
        templates << "#{category} em #{city} - Confira as Novidades"
        templates << "Imobiliária em #{city} - Veja #{category}"
        templates << "Seleção de #{category} em #{city} e Região"
      end
    end
    
    # Select a template deterministically based on page content to avoid SEO flickering
    # Using params hash ensures the same search always yields the same title
    seed = params.to_s.chars.sum(&:ord)
    selected_title = templates[seed % templates.length]
    
    # Append minimal suffix
    "#{selected_title} (#{count}) | #{public_site_name}"
  end
  
  def build_index_description
    city = location_label(default: "Balneário Camboriú")
    category = category_label(default: "imóveis")
    
    # Varied Hooks/Intros
    intros = [
      "Procurando por #{category.downcase} em #{city}?",
      "Descubra as melhores opções de #{category.downcase} em #{city}.",
      "#{public_site_name} selecionou #{category.downcase} incríveis em #{city} para você.",
      "Não feche negócio antes de ver estes #{category.downcase} em #{city}.",
      "Seu sonho de morar em #{city} comece aqui com estes #{category.downcase}."
    ]
    
    # Varied CTAs/Closings
    ctas = [
      "Agende sua visita hoje mesmo!",
      "Confira fotos e detalhes exclusivos.",
      "Fale com nossos corretores especialistas.",
      "Acesse e veja todas as oportunidades.",
      "Venha conhecer seu novo lar."
    ]
    
    # Select deterministically
    seed = params.to_s.chars.sum(&:ord)
    intro = intros[seed % intros.length]
    cta = ctas[(seed + 1) % ctas.length]
    
    # Features List
    features = []
    features << "frente mar" if params[:vista_frente_mar_flag] == '1'
    features << "mobiliado" if params[:mobiliado_flag] == '1'
    features << "com valor reduzido" if @discounted_results_present
    
    feature_text = features.any? ? " Opções com #{features.join(', ')}." : ""
    
    "#{intro}#{feature_text} Temos diversas opções à sua espera. #{cta}"
  end
  
  def build_index_keywords
    keywords = Set.new(["imóveis", "imobiliária", "balneário camboriú", public_site_name.downcase])
    
    # Transaction
    keywords << 'venda' if params[:transaction_type] == 'venda'
    keywords << 'aluguel' << 'locação' if params[:transaction_type] =~ /aluguel|locacao/
    
    # Category
    selected_categories.each { |category| keywords << category.downcase }
    
    # Location (critical keywords)
    selected_locations.each { |location| keywords << location.downcase }
    keywords << params[:bairro].downcase if params[:bairro].present?
    keywords << 'praia brava' << 'centro' << 'barra sul' # Common searches
    
    # High-value characteristics
    keywords << 'frente mar' << 'vista mar' if params[:vista_frente_mar_flag] == '1'
    keywords << 'piscina' if params[:piscina_flag] == '1'
    keywords << 'mobiliado' if params[:mobiliado_flag] == '1'
    keywords << 'cobertura' if selected_categories.include?('Cobertura')
    keywords << 'apartamento alto padrão' if params[:min_price].to_i > 1_000_000
    
    # Valor reduzido/Oportunidade
    if @discounted_results_present
      keywords << 'valor reduzido' << 'promoção' << 'oportunidade' << 'desconto'
    end
    
    keywords.to_a.join(', ')
  end

  def redirect_to_canonical_habitation_url
    return unless @habitation&.publicly_viewable?
    return unless request.get? && request.format.html?
    return unless request.path.start_with?("/imovel/")

    canonical_path = habitation_path(@habitation)
    return if request.path == canonical_path

    target = request.query_string.present? ? "#{canonical_path}?#{request.query_string}" : canonical_path
    redirect_to target, status: :moved_permanently
  end

  def public_site_name
    @layout_setting&.site_name.presence || "Unitymob"
  rescue StandardError
    "Unitymob"
  end

  def discounted_results_present?
    @habitations.any? do |habitation|
      previous = habitation.valor_venda_anterior_cents.to_i
      current = habitation.valor_venda_cents.to_i
      previous.positive? && current.positive? && previous > current
    end
  end

  def cached_listing_total_entries(scope, filters)
    Rails.cache.fetch(Habitation.public_listing_count_cache_key(public_tenant.id, filters), expires_in: 15.minutes) do
      scope.count
    end
  end

  def selected_categories
    Array(params[:category]).reject(&:blank?)
  end

  def selected_locations
    Array(params[:city]).reject(&:blank?).map { |value| value.to_s.force_encoding('UTF-8').scrub }
  end

  def category_label(default: "Imóveis")
    categories = selected_categories
    return default if categories.blank?
    return categories.first.to_s.force_encoding('UTF-8').scrub if categories.size == 1

    "#{categories.first.to_s.force_encoding('UTF-8').scrub} +#{categories.size - 1}"
  end

  def location_label(default: "Balneário Camboriú")
    locations = selected_locations
    return default if locations.blank?
    return locations.first if locations.size == 1

    "#{locations.first} +#{locations.size - 1}"
  end

  def default_property_description(habitation)
    base = [
      habitation.display_title,
      habitation.categoria,
      habitation.bairro,
      habitation.cidade
    ].compact.join(" • ")
    description = habitation.display_description.to_s.gsub(/<[^>]*>/, " ").squish
    [base, description].reject(&:blank?).join(" - ").truncate(220)
  end

  def share_image_metadata_for(habitation)
    source = habitation.primary_image_source
    attachment = source.try(:[], "attachment") || source.try(:[], :attachment)

    if attachment&.blob&.image?
      variant = attachment.blob.variant(
        resize_to_fill: [1200, 630],
        format: :jpg,
        saver: { quality: 82, strip: true }
      )
      return {
        url: "#{request.base_url}#{Rails.application.routes.url_helpers.rails_representation_path(variant, only_path: true)}",
        width: 1200,
        height: 630,
        type: "image/jpeg"
      }
    end

    image = helpers.public_image_url(source) if source.present?
    image = habitation.primary_image_url if image.blank?
    return {} if image.blank?

    { url: absolute_social_image_url(image) }
  rescue StandardError => e
    Rails.logger.warn("[social_image] habitation_id=#{habitation.id} error=#{e.class}: #{e.message}")
    image = habitation.primary_image_url
    image.present? ? { url: absolute_social_image_url(image) } : {}
  end

  def absolute_social_image_url(image)
    value = image.to_s
    return value.sub("http://", "https://") if value.start_with?("http://")
    return value if value.start_with?("https://")

    "#{request.base_url}#{value.start_with?('/') ? value : "/#{value}"}"
  end

end
