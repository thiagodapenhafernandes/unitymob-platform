require "net/http"

class HabitationsController < ApplicationController
  SOCIAL_IMAGE_TRANSFORMATIONS = { resize_to_limit: [1200, 1200] }.freeze
  SOCIAL_IMAGE_PROBE_TIMEOUT = 2
  SOCIAL_IMAGE_PROBE_ATTEMPTS = 2
  SOCIAL_IMAGE_PROBE_USER_AGENT = "WhatsApp/2.23.20.0".freeze

  include HabitationCaching
  include PublicPageCache
  include PublicListingSearch
  skip_before_action :load_layout_settings, only: %i[index show]
  include ActionView::Helpers::NumberHelper
  before_action :set_habitation, only: [:show, :schedule_visit]
  before_action :redirect_to_canonical_habitation_url, only: [:show]
  public_page_cache :index, :show
  before_action :authenticate_admin_user!, only: [:share_link]
  before_action :set_shareable_habitation, only: [:share_link]
  
  # GET /habitations
  # GET /imoveis
  def index
    return if redirect_exact_public_code
    return if apply_listing_url_params
    apply_friendly_search_params
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

    @habitations = listing_scope
      .includes(*PublicListingSearch::PUBLIC_LISTING_INCLUDES)
      .paginate(page: requested_public_listing_page, per_page: PUBLIC_LISTING_PER_PAGE, total_entries: total_entries)
    PublicSite::CardPhotoPreloader.new(@habitations.to_a, limit: 3).call
    if request.headers["Turbo-Frame"] == "public-listing-grid" && request.format.html?
      return render partial: "listing_grid", layout: false
    end

    load_filter_options
    
    # SEO page name
    @page_name = 'imoveis'
    @discounted_results_present = discounted_results_present?
    
    # Definir meta tags para SEO
    @listing_heading = [category_label, { "venda" => "à venda", "aluguel" => "para alugar", "locacao" => "para alugar" }[params[:transaction_type]], "em", selected_locations.presence&.to_sentence || location_label].compact.join(" ")
    @page_title = build_index_title
    @page_description = build_index_description
    @page_keywords = build_index_keywords
    if @strategic_landing.present?
      @listing_heading = @strategic_landing[:title]
      @page_title = "#{@strategic_landing[:title]} | #{public_site_name}"
      @page_description = @strategic_landing[:description]
      @page_keywords = [@strategic_landing[:label], "imóveis", default_public_city, public_site_name].compact_blank.join(", ")
    end
    
    listing_identity = Seo::PageIdentity.new(self).to_h
    @page_robots = "noindex, follow, max-image-preview:large" unless listing_identity[:robots_index]
    if listing_identity[:normalized_params].present?
      @canonical_url = "#{public_tenant.public_base_url(fallback_base_url: request.base_url)}#{listing_identity[:canonical_path]}"
      @page_title_priority = @page_description_priority = true
    end

    if requested_public_listing_page > 1
      canonical_params = request.query_parameters.except("share_token").reject { |key, _| key.match?(Seo::PageIdentity::IGNORED_PARAMS) }
      canonical_params["page"] = requested_public_listing_page
      @canonical_url = "#{request.base_url}#{request.path}?#{canonical_params.to_query}"
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
      redirect_to public_habitation_details_path(property), notice: "Imóvel ##{code} encontrado!"
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
      codigos = public_habitation_scope.active
                                      .where("codigo ILIKE ?", "%#{term}%")
                                      .order(:codigo)
                                      .limit(5)

      results += codigos.map do |habitation|
        {
          label: "#{habitation.codigo} - #{habitation.display_title}",
          value: habitation.codigo,
          type: "codigo",
          url: public_habitation_details_path(habitation)
        }
      end

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
      
      results += empreendimentos.map do |e| 
        { 
          label: "#{e.nome_empreendimento} (Empreendimento)", 
          value: e.nome_empreendimento, 
          type: 'empreendimento',
          url: public_habitation_details_path(e)
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

    ActiveRecord::Associations::Preloader.new(
      records: @habitation.photos_attachments.map(&:blob),
      associations: { variant_records: { image_attachment: :blob } }
    ).call
    load_share_context
    @public_map = PublicMaps::PropertyPresentation.new(@habitation)

    # Incrementar contador de visualizações (em background)
    # increment_view_count(@habitation.id)
    
    property_metadata = Seo::PropertyMetadataBuilder.new(@habitation).attributes
    @page_title = public_habitation_page_title(property_metadata)
    @page_description = property_metadata[:meta_description].presence || default_property_description(@habitation)
    @social_title = public_habitation_page_title(meta_title: property_metadata[:og_title])
    @social_description = property_metadata[:og_description]
    @page_keywords = property_metadata[:meta_keywords]
    @page_name = property_metadata[:page_name]
    @canonical_url = absolute_public_url_for_path(property_metadata[:canonical_path])
    @social_url = request.original_url if params[:share_token].present?
    
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
      PublicSite::CardPhotoPreloader.new(@development_units, limit: 3).call

      # Sem isso, a página de empreendimento nunca ganhava Cache-Control
      # público nem suporte a 304 (ao contrário do imóvel comum, que já usa
      # cache_show_page): todo hit processava a página inteira de novo, com
      # ETag baseado no próprio habitation + na lista de unidades (muda se
      # uma unidade for adicionada/removida/atualizada sem o habitation
      # "pai" mudar).
      if cache_shared_property_page?
        no_store
      else
        fresh_when(
          etag: [@habitation, @development_units, public_show_asset_cache_key],
          last_modified: @habitation.updated_at,
          public: true
        )
      end

      # Usar template específico para empreendimentos
      render 'empreendimento_show' unless performed?
      return
    end
    
    load_related_properties

    load_property_page_context

    # Links privados por token não devem ser armazenados por cache compartilhado.
    if cache_shared_property_page?
      no_store
    else
      cache_show_page(@habitation)
    end
    
    respond_to do |format|
      format.html
      format.json { render json: @habitation.card_data }
    end
  end

  def share_link
    unless shareable_commercial_status?(@habitation)
      Rails.logger.info(
        "[HabitationShare] blocked non-commercial-status habitation_id=#{@habitation.id} status=#{@habitation.status.inspect}"
      )
      return render json: {
        success: false,
        error: "Este imóvel só pode ser compartilhado quando estiver com status Venda ou Aluguel."
      }, status: :unprocessable_entity
    end

    social_photo = ensure_social_photo_public!(@habitation)
    unless social_photo[:ready]
      return render json: {
        success: false,
        error: "A foto do imóvel ainda está sendo preparada. Tente compartilhar novamente em instantes."
      }, status: :unprocessable_entity
    end

    link = HabitationShareLink.create_or_reuse_for(
      habitation: @habitation,
      admin_user: current_admin_user
    )
    link.touch

    render json: {
      success: true,
      url: habitation_url(@habitation.id, lookup: "id", share_token: link.token, preview: link.updated_at.to_i),
      expires_at: link.expires_at.iso8601
    }
  rescue StandardError => e
    Rails.logger.error "[HabitationShare] erro ao gerar link: #{e.message}"
    render json: { success: false, error: "Não foi possível gerar o link de compartilhamento." }, status: :unprocessable_entity
  end
  
  private

  def shareable_commercial_status?(habitation)
    habitation.shareable_commercial_status?
  end

  def ensure_social_photo_public!(habitation)
    source = habitation.primary_image_source
    attachment = source.try(:[], "attachment") || source.try(:[], :attachment)
    return social_image_ready_from_source(source) unless attachment&.blob&.image?

    Storage::PublicPropertyPhoto.publish_attachment!(attachment)
    variant = attachment.blob.variant(**SOCIAL_IMAGE_TRANSFORMATIONS)
    variant_image = variant.image if variant.respond_to?(:image)

    if variant_image&.attached?
      Storage::PublicPropertyPhoto.publish_blob!(variant_image.blob, raise_errors: true)
      variant_url = Storage::PublicPropertyPhoto.public_url_for_blob(variant_image.blob, tenant: habitation.tenant)
      return { ready: true, url: variant_url } if social_image_url_accessible?(variant_url)
    else
      Storage::PrepareSocialImageJob.perform_later(
        habitation.id,
        attachment.id,
        tenant_id: habitation.tenant_id,
        transformations: SOCIAL_IMAGE_TRANSFORMATIONS
      )
    end

    original_url = Storage::PublicPropertyPhoto.public_url_for_attachment(attachment)
    return { ready: true, url: original_url } if social_image_url_accessible?(original_url)

    { ready: false, url: original_url }
  rescue StandardError => e
    Rails.logger.warn("[social_image_publish] habitation_id=#{habitation.id} error=#{e.class}: #{e.message}")
    { ready: false, url: nil }
  end

  def social_image_ready_from_source(source)
    url = Storage::PublicCdnImageUrl.resolve(source)
    return { ready: true, url: nil } if url.blank?

    # URLs de payload já passam pelo allowlist do resolver; não fazemos probe
    # aqui para não bloquear compartilhamento de fotos importadas já públicas.
    { ready: true, url: url }
  end

  def social_image_url_accessible?(url, attempts: SOCIAL_IMAGE_PROBE_ATTEMPTS)
    return false if url.blank?

    uri = URI.parse(url.to_s)
    return false unless uri.is_a?(URI::HTTP)

    attempts.times do |attempt|
      return true if social_image_probe_success?(uri)

      sleep 0.25 if attempt < attempts - 1
    end

    false
  rescue URI::InvalidURIError, StandardError => e
    Rails.logger.warn("[social_image_probe] url=#{url.to_s.truncate(120)} error=#{e.class}: #{e.message}")
    false
  end

  def social_image_probe_success?(uri)
    response = perform_social_image_probe(uri, Net::HTTP::Head)
    return true if social_image_probe_response_success?(response)
    return false unless response.is_a?(Net::HTTPMethodNotAllowed) || response.is_a?(Net::HTTPForbidden)

    social_image_probe_response_success?(perform_social_image_probe(uri, Net::HTTP::Get))
  end

  def perform_social_image_probe(uri, request_class)
    Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: SOCIAL_IMAGE_PROBE_TIMEOUT,
      read_timeout: SOCIAL_IMAGE_PROBE_TIMEOUT
    ) do |http|
      request = request_class.new(uri)
      request["User-Agent"] = SOCIAL_IMAGE_PROBE_USER_AGENT
      request["Range"] = "bytes=0-0" if request.is_a?(Net::HTTP::Get)
      http.request(request)
    end
  end

  def social_image_probe_response_success?(response)
    response.is_a?(Net::HTTPSuccess) && response["content-type"].to_s.start_with?("image/")
  end

  def set_shareable_habitation
    scope = current_admin_user.tenant.habitations
    @habitation = internal_id_lookup? ? scope.find_by(id: params[:id]) : find_habitation_in_scope(params[:id], scope)
    return if @habitation

    render json: { success: false, error: "Imóvel não encontrado nesta conta." }, status: :not_found
  end

  def internal_id_lookup?
    params[:lookup].to_s.split(":", 2).first == "id"
  end
  
  def set_habitation
    @habitation = find_public_habitation(params[:id])
    return if @habitation&.publicly_viewable?
    return if valid_share_token_for?(@habitation)

    unless @habitation
      render plain: "Imóvel não encontrado.", status: :not_found
      return
    end

    reason = @habitation&.public_unavailable_reason || "nao encontrado"
    Rails.logger.info("[HabitationPublicShow] id=#{params[:id].inspect} indisponivel: #{reason}")
    redirect_to habitations_path, alert: 'Imóvel não encontrado ou indisponível no momento.'
  end

  def valid_share_token_for?(habitation)
    return false unless habitation
    return false unless shareable_commercial_status?(habitation)

    token = params[:share_token].to_s.strip
    return false if token.blank?

    HabitationShareLink.active.exists?(token: token, habitation_id: habitation.id)
  end

  def find_public_habitation(identifier)
    if internal_id_lookup?
      habitation = public_habitation_lookup_scope.find_by(id: identifier)
      return habitation if habitation
    end

    find_habitation_in_scope(identifier, public_habitation_lookup_scope)
  end

  def find_habitation_in_scope(identifier, scope)
    identifier = identifier.to_s.strip
    return nil if identifier.blank?

    lookup_scope = scope.includes(:address, photos_attachments: :blob)
    lookup_scope.find_by(slug: identifier) ||
      lookup_scope.find_by(codigo: identifier) ||
      find_habitation_by_friendly_id(identifier, lookup_scope) ||
      find_habitation_by_trailing_code(identifier, lookup_scope)
  end

  def public_habitation_scope
    public_tenant.habitations
  end

  # Imóveis relacionados (mesma região, quartos e faixa de preço ±20%).
  def load_related_properties
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
        PublicSite::CardPhotoPreloader.new(@related_properties, limit: 3).call
      end
    end
  end

  def load_neighborhood_properties
    @neighborhood_properties = []
    neighborhood = @habitation.public_neighborhood
    city = @habitation.address&.cidade.presence || @habitation.cidade
    if neighborhood.present? && city.present?
      excluded_ids = [@habitation.id, *Array(@related_properties).map(&:id)]
      price_column = @habitation.valor_venda_cents.to_i.positive? ? :valor_venda_cents : :valor_locacao_cents
      @neighborhood_properties = public_habitation_scope
        .public_property_listable
        .by_public_locations(["#{neighborhood} - #{city}"])
        .where(price_column => 1..)
        .where.not(id: excluded_ids)
        .includes(:address, { constructor: { logo_attachment: :blob } }, { empreendimento: { constructor: { logo_attachment: :blob } } })
        .newest_first
        .limit(6)
        .to_a
      PublicSite::CardPhotoPreloader.new(@neighborhood_properties, limit: 3).call
    end
  end

  # Blocos do detalhe no formato "página de imóvel completa": empreendimento
  # do imóvel (fotos, lazer, faixas), mais imóveis no mesmo bairro e links de
  # imóveis por cidade.
  def load_property_page_context
    development = @habitation.empreendimento
    @property_development = development if development && development.id != @habitation.id
    if @property_development
      ActiveRecord::Associations::Preloader.new(
        records: [@property_development],
        associations: { photos_attachments: { blob: { variant_records: { image_attachment: :blob } } } }
      ).call
    end
    @public_site_profile = PublicSiteProfile.current(tenant: public_tenant)
    @show_development_identity = @public_site_profile.show_development_identity?
    # Simulador na página (e na ETag): muda quando a conta liga/desliga ou a taxa muda.
    @financing_cache_key = if @public_site_profile.financing_simulator_enabled?
                             [@public_site_profile.financing_rate.cache_key, @public_site_profile.financing_market_rate.cache_key].join("|")
                           end

    load_neighborhood_properties

    @city_link_groups = Rails.cache.fetch("public_city_link_groups_v1/tenant/#{public_tenant.id}", expires_in: 6.hours) do
      public_habitation_scope.public_city_link_groups
    end
  end

  def public_habitation_lookup_scope
    public_habitation_scope.includes(
      { photos_attachments: :blob },
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

  def apply_strategic_landing_params
    @strategic_landing = Seo::StrategicLanding.property(params[:seo_slug])
    return if @strategic_landing.blank?

    @strategic_landing[:params].each do |key, value|
      params[key] = value
    end
  end

  def apply_friendly_search_params
    return if params[:friendly_transaction].blank?

    PublicSearch::FriendlyUrl.new(tenant: public_tenant).params_for(params).each do |key, value|
      params[key] = value
    end
  end

  # Core novo de URLs amigáveis (/imoveis/venda/... gramática completa).
  # Retorna true quando respondeu (404 de slug desconhecido ou 301 de
  # limpeza de `todos`); senão injeta os filtros no params e retorna false.
  # O legado abaixo segue intacto.
  # Busca por código exato vai direto à página do imóvel em vez da listagem.
  def redirect_exact_public_code
    term = params[:search].presence || params[:q].presence
    return false if term.blank?

    property = Habitation.find_public_code_in(public_tenant.habitations.public_property_listable, term)
    return false if property.blank?

    redirect_to public_habitation_details_path(property)
    true
  end

  def apply_listing_url_params
    return true if redirect_canonical_listing_search?

    if params[:listing_transaction].present?
      parsed = PublicSearch::ListingUrl.new(tenant: public_tenant)
        .params_for(params[:listing_transaction], params[:listing_filters])
      if parsed.nil?
        render plain: "Not Found", status: :not_found
        return true
      end

      parsed.each { |key, value| params[key] = value }
    elsif params[:friendly_transaction].blank?
      return false
    else
      apply_friendly_search_params
      repair_friendly_location_categories
      # Consome os segmentos para o apply_friendly do index não refazer o
      # parse por cima (desfaria o reparo acima).
      params.delete(:friendly_transaction)
      params.delete(:friendly_categories)
      params.delete(:friendly_locations)
      params.delete(:friendly_characteristics)
    end

    return false unless todos_in_listing_path?

    redirect_to canonical_listing_url, status: :moved_permanently
    true
  end

  # Submit dos forms públicos (marcador v=2): redireciona o GET /imoveis
  # com filtros para a gramática nova. URLs antigas (sem marcador)
  # continuam respondendo 200 em paralelo — nada quebra para campanhas.
  def redirect_canonical_listing_search?
    return false unless params[:v].to_s == "2"
    return false unless request.get? && request.format.html?
    return false if params[:listing_transaction].present?
    return false if params[:seo_slug].present?

    # Links com v=2 vindos de página legada trazem friendly_* na query:
    # injeta primeiro para não perder transação/categoria/cidade.
    apply_friendly_search_params if params[:friendly_transaction].present?

    filters = search_params
    if listing_filters_present?(filters)
      redirect_to canonical_listing_url, status: :moved_permanently
    else
      redirect_to habitations_path, status: :moved_permanently
    end
    true
  end

  def listing_filters_present?(filters)
    %i[
      transaction_type category city bedrooms min_bedrooms suites min_suites
      parking min_parking bathrooms min_bathrooms min_area max_area min_price max_price
      characteristics furnished accepts_exchange accepts_financing search
    ].any? { |key| filters[key].present? }
  end

  # O legado lê o 2º segmento sempre como categoria; quando o rótulo não
  # é um tipo de imóvel mas é uma localidade do tenant (ex:
  # /imoveis/venda/itapema, forma que o canônico novo também emite),
  # reclassifica para city em vez de devolver página vazia.
  def repair_friendly_location_categories
    categories = normalize_filter_values(params[:category])
    return if categories.empty?

    known_categories = Rails.cache.fetch(Habitation.public_filter_property_types_cache_key(public_tenant.id), expires_in: 12.hours) do
      public_tenant.habitations.public_property_types
    end.map { |value| PublicSearch::ListingUrl.slug(value) }
    location_lookup = Rails.cache.fetch(Habitation.public_filter_location_options_cache_key(public_tenant.id), expires_in: 6.hours) do
      public_tenant.habitations.public_location_options
    end.map { |option| option[:value].to_s }
      .index_by { |value| PublicSearch::ListingUrl.slug(value) }

    moved, kept = categories.partition do |label|
      slug = PublicSearch::ListingUrl.slug(label)
      known_categories.exclude?(slug) && location_lookup.key?(slug)
    end
    return if moved.empty?

    params[:category] = kept
    params[:city] = (normalize_filter_values(params[:city]) + moved.map { location_lookup[PublicSearch::ListingUrl.slug(_1)] }).uniq
  end

  def todos_in_listing_path?
    params[:listing_filters].to_s.split("/").any? do |segment|
      segment.to_s.split("+").any? { |part| PublicSearch::ListingUrl.blank_segment?(part) }
    end
  end

  # Filtros consumidos pelo path novo; o resto (page, sort e escapes como
  # development) continua como query string no redirect canônico.
  LISTING_PATH_FILTER_KEYS = %w[
    transaction_type finalidade category tipo city cidade
    bedrooms min_bedrooms suites min_suites parking min_parking bathrooms min_bathrooms
    min_area max_area min_price max_price price_range
    characteristics furnished accepts_exchange accepts_financing
    frente_mar quadra_mar varanda search q seo_slug
    friendly_transaction friendly_categories friendly_locations friendly_characteristics
    listing_transaction listing_filters v
  ].freeze

  def canonical_listing_url
    path = PublicSearch::ListingUrl.build(search_params)
    query = request.query_parameters.except(*LISTING_PATH_FILTER_KEYS).compact_blank
    query.delete("page") if query["page"].to_i <= 1
    query_string = query.to_query
    query_string.present? ? "#{path}?#{query_string}" : path
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

  def cache_shared_property_page?
    params[:share_token].present? || @share_link.present?
  end

  def remember_share_link(link)
    cookies.signed[HabitationShareLink::COOKIE_KEY] = {
      value: link.token,
      expires: HabitationShareLink.expiration_period(tenant: @habitation.tenant).from_now,
      same_site: :lax,
      httponly: true
    }
  end
  
  def visit_params
    params.permit(:name, :email, :phone, :preferred_date, :preferred_time, :message)
  end
  
  # SEO OPTIMIZATION - Dynamic & Varied Meta Tags (Style: Conexão Imobiliária)
  def build_index_title
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
    # Normalized filters keep campaign parameters out of the title selection
    seed = Seo::PageIdentity.new(self).to_h.fetch(:normalized_params, {}).to_json.chars.sum(&:ord)
    selected_title = templates[seed % templates.length]
    
    # Append minimal suffix
    "#{selected_title} | #{public_site_name}"
  end
  
  def build_index_description
    city = location_label(default: default_public_city)
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
    seed = Seo::PageIdentity.new(self).to_h.fetch(:normalized_params, {}).to_json.chars.sum(&:ord)
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
    keywords = Set.new(["imóveis", "imobiliária", default_public_city.to_s.downcase, public_site_name.downcase].compact_blank)
    
    # Transaction
    keywords << 'venda' if params[:transaction_type] == 'venda'
    keywords << 'aluguel' << 'locação' if params[:transaction_type] =~ /aluguel|locacao/
    
    # Category
    selected_categories.each { |category| keywords << category.downcase }
    
    # Location (critical keywords)
    selected_locations.each { |location| keywords << location.downcase }
    keywords << params[:bairro].downcase if params[:bairro].present?
    
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

    canonical_path = public_habitation_details_path(@habitation)
    canonical_request = request.path == canonical_path
    legacy_property_path = request.path.start_with?("/imovel/")
    legacy_development_path = @habitation.empreendimento? && request.path.start_with?("/imoveis/")
    return if canonical_request || (!legacy_property_path && !legacy_development_path)

    return if request.path == canonical_path

    target = request.query_string.present? ? "#{canonical_path}?#{request.query_string}" : canonical_path
    redirect_to target, status: :moved_permanently
  end

  def public_habitation_details_path(habitation)
    habitation.empreendimento? ? empreendimento_details_path(habitation) : habitation_path(habitation)
  end

  def public_habitation_page_title(property_metadata)
    title = property_metadata[:meta_title]
    return title if @habitation.empreendimento?

    [@habitation.codigo.presence, title].compact.join(" - ")
  end

  def absolute_public_url_for_path(path)
    value = path.to_s
    return value if value.start_with?("http://", "https://")

    "#{request.base_url}#{value.start_with?("/") ? value : "/#{value}"}"
  end

  def public_site_name
    @layout_setting&.site_name.presence || "Unitymob"
  rescue StandardError
    "Unitymob"
  end

  def default_public_city
    Tenants::PublicIdentity.new(public_tenant).primary_city.presence || "Brasil"
  end

  def discounted_results_present?
    @habitations.any? { |habitation| habitation.sale_discount? || habitation.rent_discount? }
  end


  def public_page_cache_query_allowed?
    !request.query_parameters.key?("share_token")
  end

  def public_page_cache_key
    # Visitas personalizadas por cookie de compartilhamento nunca usam a entrada compartilhada.
    return if cookies.signed[HabitationShareLink::COOKIE_KEY].present?

    base = super
    return unless base

    # Cada busca e atribuição tem sua entrada: os links continuam com a query correta.
    [base, Digest::SHA256.hexdigest(request.query_parameters.sort.to_h.to_query)].join("/")
  end

  def selected_categories
    normalize_filter_values(params[:category])
  end

  def selected_locations
    normalize_filter_values(params[:city]).map { |value| value.to_s.force_encoding('UTF-8').scrub }
  end

  def category_label(default: "Imóveis")
    categories = selected_categories
    return default if categories.blank?
    return categories.first.to_s.force_encoding('UTF-8').scrub if categories.size == 1

    "#{categories.first.to_s.force_encoding('UTF-8').scrub} +#{categories.size - 1}"
  end

  def location_label(default: default_public_city)
    locations = selected_locations
    return default if locations.blank?
    return locations.first if locations.size == 1

    "#{locations.first} +#{locations.size - 1}"
  end

  def default_property_description(habitation)
    base = [
      habitation.display_title,
      habitation.categoria,
      habitation.public_neighborhood,
      habitation.cidade
    ].compact.join(" • ")
    description = habitation.display_description.to_s.gsub(/<[^>]*>/, " ").squish
    [base, description].reject(&:blank?).join(" - ").truncate(220)
  end

  # Metatag og:image: só dados (sem HTML), com cache — evita repetir
  # resolução de variantes a cada hit do detalhe.
  def share_image_metadata_for(habitation)
    Rails.cache.fetch(
      ["social_image_v1", habitation.id, habitation.updated_at.to_i,
       Digest::MD5.hexdigest(habitation.pictures.to_s)].join("/"),
      expires_in: 12.hours
    ) do
      uncached_share_image_metadata_for(habitation)
    end
  end

  def uncached_share_image_metadata_for(habitation)
    source = habitation.primary_image_source
    attachment = source.try(:[], "attachment") || source.try(:[], :attachment)

    if attachment&.blob&.image?
      variant_metadata = social_variant_metadata_for(attachment)
      return variant_metadata if variant_metadata.present?

      cdn_url = Storage::PublicPropertyPhoto.public_url_for_attachment(attachment)
      return { url: cdn_url, type: attachment.blob.content_type } if cdn_url.present?
    end

    # Imóveis importados (Vista/DWV) guardam as fotos como URL externa, não como
    # attachment. Sem este fallback o og:image caía no icon.png e o link
    # compartilhado (WhatsApp/redes) subia sem a foto do imóvel.
    external_url = Storage::PublicCdnImageUrl.resolve(source)
    return { url: external_url } if external_url.present?

    {}
  rescue StandardError => e
    Rails.logger.warn("[social_image] habitation_id=#{habitation.id} error=#{e.class}: #{e.message}")
    {}
  end

  def social_variant_metadata_for(attachment)
    variant = attachment.blob.variant(**SOCIAL_IMAGE_TRANSFORMATIONS)
    return unless variant.respond_to?(:image)

    variant_image = variant.image
    return unless variant_image&.attached?

    variant_url = Storage::PublicPropertyPhoto.public_url_for_blob(variant_image.blob)
    return if variant_url.blank?

    { url: variant_url, type: variant_image.blob.content_type }
  rescue StandardError => e
    Rails.logger.warn("[social_image_variant] blob_id=#{attachment.blob_id} error=#{e.class}: #{e.message}")
    nil
  end

  def absolute_social_image_url(image)
    value = image.to_s
    if value.start_with?("http://", "https://")
      uri = URI.parse(value.sub("http://", "https://"))
      uri.path = uri.path.gsub(%r{/+}, "/")
      return uri.to_s
    end

    "#{request.base_url}#{value.start_with?('/') ? value : "/#{value}"}"
  rescue URI::InvalidURIError
    value
  end

end
