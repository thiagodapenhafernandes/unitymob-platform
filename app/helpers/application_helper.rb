module ApplicationHelper
  # Faixas da busca pública (hero e listagem): personalizadas pela conta no
  # Perfil público; senão calculadas pelo estoque (PublicSite::PriceRanges);
  # senão as faixas padrão abaixo.
  def public_price_range_options(transaction_type = nil)
    rental = public_rental_transaction?(transaction_type)
    profile = PublicSiteProfile.current(tenant: public_tenant)
    if profile.custom_price_ranges?
      configured = rental ? profile.rental_price_options : profile.sale_price_options
      return [["Todos os Valores", ""], *configured] if configured.any?
    end

    automatic = PublicSite::PriceRanges.for(public_tenant).dig(rental ? "aluguel" : "venda", :ranges)
    return [["Todos os Valores", ""], *automatic] if automatic.present?

    if rental
      [
        ["Todos os Valores", ""],
        ["até R$5.000", "0-5000"],
        ["R$5.000 ↔ R$10.000", "5000-10000"],
        ["R$10.000 ↔ R$15.000", "10000-15000"],
        ["R$15.000 ↔ R$20.000", "15000-20000"],
        ["R$20.000 ↔ R$25.000", "20000-25000"],
        ["Acima R$25.000", "25000-"]
      ]
    else
      [
        ["Todos os Valores", ""],
        ["até R$1.000.000", "0-1000000"],
        ["R$1.000.000 ↔ R$2.000.000", "1000000-2000000"],
        ["R$2.000.000 ↔ R$3.000.000", "2000000-3000000"],
        ["R$3.000.000 ↔ R$5.000.000", "3000000-5000000"],
        ["R$5.000.000 ↔ R$10.000.000", "5000000-10000000"],
        ["a partir de R$10.000.000", "10000000-"]
      ]
    end
  end

  # Limites do slider de valor do drawer, pelo estoque da conta (com padrão).
  def public_price_slider_bounds(transaction_type)
    rental = public_rental_transaction?(transaction_type)
    defaults = rental ? { min: 5_000, max: 50_000, step: 1_000 } : { min: 1_000_000, max: 50_000_000, step: 100_000 }
    stats = PublicSite::PriceRanges.for(public_tenant)[rental ? "aluguel" : "venda"]
    stats ? stats.slice(:min, :max, :step) : defaults
  end

  def public_rental_transaction?(transaction_type)
    transaction_type.to_s.downcase.in?(%w[aluguel locacao locação alugar])
  end

  def public_pwa_icon_path(size: 512)
    version = @layout_setting&.updated_at&.to_i || LayoutSetting.instance(tenant: public_tenant)&.updated_at&.to_i || 0
    "/pwa-icon-#{size}?v=#{version}"
  end

  def public_pwa_icon_url(size: 512)
    "#{request.base_url}#{public_pwa_icon_path(size: size)}"
  end

  def public_image_url(source, resize_to_limit: nil, resize_to_fill: nil, format: nil, quality: nil, strip: nil, saver: { quality: 82 }, force_variant: false, proxy: true, representation_proxy: false)
    profile = Storage::PublicImageVariants::CARD.find { |item| item[:resize_to_fill] == resize_to_fill } if format.to_s == "webp"
    if profile
      quality ||= profile[:quality]
      strip = profile[:strip] if strip.nil?
    end
    Storage::PublicCdnImageUrl.resolve(
      source,
      resize_to_limit:,
      resize_to_fill:,
      format:,
      quality:,
      strip:,
      saver:,
      force_variant:,
      proxy:,
      representation_proxy:
    )
  end

  # Resolve o partial do componente do tema atual (com fallback para o
  # default): a view pede theme_component(:property_card) e o tema responde
  # com seu render próprio, sem condicionais espalhadas.
  def theme_component(name, **locals, &block)
    entry = theme_component_entry(name)
    render entry[:partial], **locals.merge(variant: entry[:variant]), &block
  end

  def theme_component_path(name)
    theme_component_entry(name)[:partial]
  end

  def theme_variant
    theme_component_entry(:property_card)[:variant]
  end

  def theme_component_entry(name)
    key = public_tenant&.public_site_theme_key || Tenant::DEFAULT_PUBLIC_SITE_THEME
    meta = Tenant::PUBLIC_SITE_THEMES[key] || {}
    partial = (meta[:components] || {})[name.to_sym]
    return { partial:, variant: meta[:variant] || "default" } if partial

    default_meta = Tenant::PUBLIC_SITE_THEMES[Tenant::DEFAULT_PUBLIC_SITE_THEME]
    { partial: default_meta[:components][name.to_sym], variant: "default" }
  end

  # URL da listagem pública preservando a busca atual: o path (URLs
  # amigáveis /imoveis/venda/... e landings /imoveis/:seo_slug guardam
  # filtros no path) mais os query params mesclados com overrides.
  # Paginação e ordenação usam este helper para não perder a referência.
  def public_listing_path(overrides = {})
    query = request.query_parameters.merge(overrides.transform_keys(&:to_s)).compact_blank
    query.delete("page") if query["page"].to_i <= 1
    query_string = query.to_query
    query_string.present? ? "#{request.path}?#{query_string}" : request.path
  end

  # Monta path da gramática nova (/imoveis/venda/...) a partir dos filtros
  # internos — fonte única server-side (PublicSearch::ListingUrl).
  def build_public_listing_path(filters = {})
    PublicSearch::ListingUrl.build(filters)
  end

  def public_habitation_detail_path(property)
    return "#" if property.blank?

    property.empreendimento? ? empreendimento_details_path(property) : habitation_path(property)
  end

  def public_image_srcset(source, widths:, aspect_ratio: nil, crop: false, format: :webp, representation_proxy: false)
    widths.filter_map do |width|
      dimensions = aspect_ratio ? [width, (width / aspect_ratio.to_f).round] : [width, width]
      transformations = crop ? { resize_to_fill: dimensions } : { resize_to_limit: dimensions }
      url = public_image_url(source, **transformations, format:, representation_proxy:)
      "#{url} #{width}w" if url.present?
    end.join(", ").presence
  end

  def public_image_fallback_urls(source)
    [
      development_signed_public_image_url(source)
    ].compact_blank
  end

  def development_signed_public_image_url(source)
    return unless Rails.env.development?

    blob =
      if defined?(ActiveStorage::Attachment) && source.is_a?(ActiveStorage::Attachment)
        source.blob
      elsif defined?(ActiveStorage::Blob) && source.is_a?(ActiveStorage::Blob)
        source
      elsif source.is_a?(Hash)
        attachment = source[:attachment] || source["attachment"]
        explicit_blob = source[:blob] || source["blob"]

        if defined?(ActiveStorage::Attachment) && attachment.is_a?(ActiveStorage::Attachment)
          attachment.blob
        elsif defined?(ActiveStorage::Blob) && explicit_blob.is_a?(ActiveStorage::Blob)
          explicit_blob
        end
      end

    return if blob.blank? || blob.key.blank?

    Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)
  rescue StandardError
    nil
  end

  def json_ld_tag(payload)
    tag.script(json_escape(payload.to_json).html_safe, type: "application/ld+json")
  end

  def real_estate_agent_schema
    identity = Tenants::PublicIdentity.new(public_tenant)
    layout = LayoutSetting.instance(tenant: public_tenant)
    logo_url = public_image_url({ attachment: layout.logo }) if layout.logo.attached?
    schema_phones = identity.schema_phones
    home_seo = SeoSetting.for_page("home", tenant: public_tenant)
    home_description = home_seo.meta_description.presence if home_seo&.public_applicable?
    map_address = identity.locations.first&.dig(:address).presence
    primary_city = identity.primary_city.presence
    location_entries = identity.locations.map do |location|
      {
        "@type" => "Place",
        "name" => location[:name],
        "address" => {
          "@type" => "PostalAddress",
          "streetAddress" => location[:address],
          "addressLocality" => primary_city,
          "postalCode" => location[:postal_code],
          "addressCountry" => "BR"
        }.compact
      }
    end

    {
      "@context" => "https://schema.org",
      "@type" => ["RealEstateAgent", "LocalBusiness"],
      "@id" => "#{request.base_url}#organization",
      "name" => identity.name,
      "description" => home_description,
      "url" => request.base_url,
      "logo" => absolute_public_url(logo_url),
      "telephone" => schema_phones.first.presence || identity.phone,
      "email" => identity.email,
      "address" => location_entries.first&.dig("address"),
      "sameAs" => identity.social_urls.presence,
      "contactPoint" => schema_phones.map do |phone|
        {
          "@type" => "ContactPoint",
          "telephone" => phone,
          "contactType" => "customer service",
          "areaServed" => "BR",
          "availableLanguage" => "Portuguese"
        }
      end.presence,
      "areaServed" => ({"@type" => "City", "name" => primary_city} if primary_city),
      "hasMap" => ("https://maps.google.com/?q=#{ERB::Util.url_encode(map_address)}" if map_address),
      "location" => location_entries.presence
    }.compact
  end

  def real_estate_listing_schema(habitation)
    price_cents = habitation.valor_venda_cents.to_i.positive? ? habitation.valor_venda_cents : habitation.valor_locacao_cents
    image_urls = habitation.public_image_sources.first(8).filter_map { |source| absolute_public_url(public_image_url(source)) }

    {
      "@context" => "https://schema.org",
      "@type" => "RealEstateListing",
      "name" => habitation.display_title,
      "description" => Seo::PropertyMetadataBuilder.new(habitation).attributes[:meta_description],
      "url" => @canonical_url.presence || absolute_public_url(habitation_path(habitation)),
      "identifier" => habitation.codigo,
      "image" => image_urls.presence,
      "address" => listing_address_schema(habitation),
      "geo" => listing_geo_schema(habitation),
      "floorSize" => listing_floor_size_schema(habitation),
      "numberOfRooms" => positive_integer_or_nil(habitation.dormitorios_qtd),
      "numberOfBathroomsTotal" => positive_integer_or_nil(habitation.banheiros_qtd),
      "aggregateRating" => public_rating_schema(habitation),
      "offers" => listing_offer_schema(habitation, price_cents)
    }.compact
  end

  def public_rating_schema(habitation)
    return unless habitation&.public_rating_configured?

    {
      "@type" => "AggregateRating",
      "ratingValue" => format("%.2f", habitation.public_rating_value_for_schema),
      "bestRating" => "5",
      "worstRating" => "0",
      "ratingCount" => habitation.public_rating_count.to_i
    }
  end

  def public_rating_value_label(habitation)
    return unless habitation&.public_rating_configured?

    number_with_precision(habitation.public_rating_value_for_schema, precision: 1, separator: ",", delimiter: ".")
  end

  def public_rating_count_label(habitation)
    count = habitation.public_rating_count.to_i
    count == 1 ? "1 avaliação" : "#{count} avaliações"
  end

  def public_rating_star_icon_names(habitation)
    value = habitation.public_rating_value_for_schema.to_f.clamp(0, 5)
    (1..5).map do |position|
      if value >= position
        "bi-star-fill"
      elsif value >= position - 0.5
        "bi-star-half"
      else
        "bi-star"
      end
    end
  end

  # SEO Helper - Dynamic meta tags
  def seo_meta_tags(page_name = 'home')
    seo = SeoSetting.for_page(page_name)
    identity = Tenants::PublicIdentity.new(public_tenant)
    fallback_description = ["Imobiliária", identity.primary_city.present? ? "em #{identity.primary_city}" : nil].compact.join(" ")
    
    content_for :meta_tags do
      tags = []
      tags << tag.meta(name: 'title', content: seo.meta_title.presence || identity.name)
      tags << tag.meta(name: 'description', content: seo.meta_description.presence || fallback_description)
      tags << tag.meta(name: 'keywords', content: seo.meta_keywords) if seo.meta_keywords.present?
      
      # Open Graph
      tags << tag.meta(property: 'og:title', content: seo.meta_title.presence || identity.name)
      tags << tag.meta(property: 'og:description', content: seo.meta_description.presence || fallback_description)
      
      tags.join("\n").html_safe
    end
  end
  
  # Banner display helper
  def display_banner(position, options = {})
    banner = public_tenant.banners.active.by_position(position).detect(&:displayable?)
    return if banner.blank?
    
    render 'shared/banner', banner: banner, options: options
  end

  # Sorting helper
  def sortable(column, title = nil)
    title ||= column.titleize
    css_class = column == sort_column ? "current #{sort_direction}" : nil
    direction = column == sort_column && sort_direction == "asc" ? "desc" : "asc"
    
    # Merge existing params with new sort params
    link_to url_for(request.query_parameters.merge(sort: column, direction: direction)), class: "text-decoration-none text-dark fw-bold d-flex align-items-center gap-1 #{css_class}" do
      concat title
      if column == sort_column
        concat tag.i(class: "bi bi-sort-#{sort_direction == 'asc' ? 'up' : 'down'}")
      else
        concat tag.i(class: "bi bi-arrow-down-up text-muted opacity-50 small")
      end
    end
  end

  private

  def absolute_url_for_asset(asset_name)
    asset_url(asset_name)
  end

  def absolute_public_url(value)
    return if value.blank?
    return value if value.match?(%r{\Ahttps?://}i)

    URI.join(request.base_url, value).to_s
  rescue URI::InvalidURIError
    nil
  end

  def listing_address_schema(habitation)
    return if habitation.cidade.blank?

    {
      "@type" => "PostalAddress",
      "streetAddress" => [habitation.tipo_endereco, habitation.endereco, habitation.numero].compact_blank.join(" ").presence,
      "addressLocality" => habitation.cidade,
      "addressRegion" => habitation.uf.presence || "SC",
      "addressCountry" => "BR",
      "postalCode" => habitation.cep
    }.compact
  end

  def listing_geo_schema(habitation)
    public_map = if defined?(@public_map) && @public_map&.property == habitation
                   @public_map
                 else
                   PublicMaps::PropertyPresentation.new(habitation)
                 end
    coordinates = public_map.center_coordinates
    return if coordinates.blank?

    latitude, longitude = coordinates

    {
      "@type" => "GeoCoordinates",
      "latitude" => latitude.to_f,
      "longitude" => longitude.to_f
    }
  end

  def listing_floor_size_schema(habitation)
    area = habitation.public_area_m2
    return if area.blank?

    {
      "@type" => "QuantitativeValue",
      "value" => area.to_f,
      "unitCode" => "MTK"
    }
  end

  def listing_offer_schema(habitation, price_cents)
    return unless price_cents.to_i.positive?

    {
      "@type" => "Offer",
      "price" => (price_cents.to_f / 100.0).round(2),
      "priceCurrency" => "BRL",
      "availability" => "https://schema.org/InStock",
      "url" => @canonical_url.presence || absolute_public_url(habitation_path(habitation))
    }
  end

  def positive_integer_or_nil(value)
    integer = value.to_i
    integer.positive? ? integer : nil
  end
end
