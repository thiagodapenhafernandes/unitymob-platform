module ApplicationHelper
  INTERNAL_ACTIVE_STORAGE_PATH = "/rails/active_storage/".freeze
  ACTIVE_STORAGE_REDIRECT_SEGMENTS = {
    "/rails/active_storage/blobs/redirect/" => "/rails/active_storage/blobs/proxy/",
    "/rails/active_storage/representations/redirect/" => "/rails/active_storage/representations/proxy/"
  }.freeze

  def optimized_image_source(source, resize_to_limit: nil, resize_to_fill: nil, saver: { quality: 82 }, force_variant: false)
    return if source.blank?

    image = if source.is_a?(Hash)
      source["attachment"] || source[:attachment] ||
        source["url_pequena"] || source[:url_pequena] ||
        source["url_small"] || source[:url_small] ||
        source["thumbnail_url"] || source[:thumbnail_url] ||
        source["url"] || source[:url]
    else
      source
    end
    return image unless image.respond_to?(:variant)
    return image unless active_storage_variants_enabled?(force: force_variant)

    transformations = {}
    transformations[:resize_to_limit] = resize_to_limit if resize_to_limit.present?
    transformations[:resize_to_fill] = resize_to_fill if resize_to_fill.present?
    transformations[:saver] = saver if saver.present?

    transformations.present? ? image.variant(transformations) : image
  end

  def active_storage_variants_enabled?(force: false)
    force || ENV["ACTIVE_STORAGE_VARIANTS_ENABLED"] == "true"
  end

  def public_price_range_options(transaction_type = nil)
    if transaction_type.to_s.downcase.in?(%w[aluguel locacao locação alugar])
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

  def public_image_url(source, resize_to_limit: nil, resize_to_fill: nil, saver: { quality: 82 }, force_variant: false)
    return if source.blank?

    image = if resize_to_limit.present? || resize_to_fill.present?
              optimized_image_source(source, resize_to_limit: resize_to_limit, resize_to_fill: resize_to_fill, saver: saver, force_variant: force_variant)
            else
              image_source_from(source)
            end

    active_storage_public_path(image) || normalize_public_image_url(image)
  end

  def json_ld_tag(payload)
    tag.script(json_escape(payload.to_json).html_safe, type: "application/ld+json")
  end

  def real_estate_agent_schema
    {
      "@context" => "https://schema.org",
      "@type" => ["RealEstateAgent", "LocalBusiness"],
      "name" => "Salute Imóveis",
      "url" => "https://saluteimoveis.com.br",
      "logo" => absolute_url_for_asset("salute-imoveis.svg"),
      "telephone" => "+554733111067",
      "email" => "contato@saluteimoveis.com",
      "sameAs" => [
        "https://www.instagram.com/saluteimoveis/",
        "https://www.facebook.com/saluteimoveisunicos/",
        "https://www.youtube.com/channel/UC9BG_PI0pFj-m65sR6KeZtA"
      ],
      "location" => [
        {
          "@type" => "Place",
          "name" => "Filial Av. Brasil",
          "address" => {
            "@type" => "PostalAddress",
            "streetAddress" => "Rua 3150, 3160",
            "addressLocality" => "Balneário Camboriú",
            "addressRegion" => "SC",
            "postalCode" => "88330-281",
            "addressCountry" => "BR"
          }
        },
        {
          "@type" => "Place",
          "name" => "Filial Av. Atlântica",
          "address" => {
            "@type" => "PostalAddress",
            "streetAddress" => "Avenida Atlântica, 3750",
            "addressLocality" => "Balneário Camboriú",
            "addressRegion" => "SC",
            "postalCode" => "88330-024",
            "addressCountry" => "BR"
          }
        }
      ]
    }
  end

  def real_estate_listing_schema(habitation)
    price_cents = habitation.valor_venda_cents.to_i.positive? ? habitation.valor_venda_cents : habitation.valor_locacao_cents
    image_urls = habitation.public_image_sources.filter_map { |source| absolute_public_url(public_image_url(source)) }

    {
      "@context" => "https://schema.org",
      "@type" => "RealEstateListing",
      "name" => habitation.display_title,
      "description" => strip_tags(habitation.seo_description.to_s).squish.presence,
      "url" => request.original_url,
      "identifier" => habitation.codigo,
      "image" => image_urls.presence,
      "address" => listing_address_schema(habitation),
      "geo" => listing_geo_schema(habitation),
      "floorSize" => listing_floor_size_schema(habitation),
      "numberOfRooms" => positive_integer_or_nil(habitation.dormitorios_qtd),
      "numberOfBathroomsTotal" => positive_integer_or_nil(habitation.banheiros_qtd),
      "offers" => listing_offer_schema(habitation, price_cents)
    }.compact
  end

  # SEO Helper - Dynamic meta tags
  def seo_meta_tags(page_name = 'home')
    seo = SeoSetting.for_page(page_name)
    
    content_for :meta_tags do
      tags = []
      tags << tag.meta(name: 'title', content: seo.meta_title || 'Salute Imóveis')
      tags << tag.meta(name: 'description', content: seo.meta_description || 'Imobiliária em Balneário Camboriú')
      tags << tag.meta(name: 'keywords', content: seo.meta_keywords) if seo.meta_keywords.present?
      
      # Open Graph
      tags << tag.meta(property: 'og:title', content: seo.meta_title || 'Salute Imóveis')
      tags << tag.meta(property: 'og:description', content: seo.meta_description || 'Imobiliária em Balneário Camboriú')
      
      tags.join("\n").html_safe
    end
  end
  
  # Banner display helper
  def display_banner(position, options = {})
    banner = Banner.active.by_position(position).detect(&:displayable?)
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

  def image_source_from(source)
    if source.respond_to?(:attached?)
      return source.attachment if source.attached?
      return
    end

    return source unless source.is_a?(Hash)

    source["attachment"] || source[:attachment] ||
      source["url"] || source[:url] ||
      source["url_pequena"] || source[:url_pequena] ||
      source["url_small"] || source[:url_small] ||
      source["thumbnail_url"] || source[:thumbnail_url]
  end

  def active_storage_public_path(image)
    return if image.blank?

    if defined?(ActiveStorage::VariantWithRecord) && image.is_a?(ActiveStorage::VariantWithRecord)
      proxy_active_storage_redirect_path(active_storage_route(:rails_representation_path, image, only_path: true))
    elsif defined?(ActiveStorage::Variant) && image.is_a?(ActiveStorage::Variant)
      proxy_active_storage_redirect_path(active_storage_route(:rails_representation_path, image, only_path: true))
    elsif image.respond_to?(:attached?)
      return unless image.attached?

      active_storage_route(:rails_storage_proxy_path, image.attachment, only_path: true)
    elsif defined?(ActiveStorage::Attachment) && image.is_a?(ActiveStorage::Attachment)
      active_storage_route(:rails_storage_proxy_path, image, only_path: true)
    elsif defined?(ActiveStorage::Blob) && image.is_a?(ActiveStorage::Blob)
      active_storage_route(:rails_storage_proxy_path, image, only_path: true)
    end
  rescue StandardError
    nil
  end

  def active_storage_route(name, *args, **options)
    return public_send(name, *args, **options) if respond_to?(name)

    Rails.application.routes.url_helpers.public_send(name, *args, **options)
  end

  def normalize_public_image_url(image)
    value = image.to_s
    return value if value.blank?
    return if value.start_with?("#<")
    return proxy_active_storage_redirect_path(value) if value.start_with?(INTERNAL_ACTIVE_STORAGE_PATH)
    return value if value.start_with?("/", "data:", "blob:")

    uri = URI.parse(value)
    return value unless uri.path.start_with?(INTERNAL_ACTIVE_STORAGE_PATH)

    proxy_active_storage_redirect_path([uri.path, uri.query.presence && "?#{uri.query}"].compact.join)
  rescue URI::InvalidURIError
    value
  end

  def proxy_active_storage_redirect_path(value)
    ACTIVE_STORAGE_REDIRECT_SEGMENTS.each do |redirect_segment, proxy_segment|
      return value.sub(redirect_segment, proxy_segment) if value.include?(redirect_segment)
    end

    value
  end

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
    return if habitation.latitude.blank? || habitation.longitude.blank?

    {
      "@type" => "GeoCoordinates",
      "latitude" => habitation.latitude.to_f,
      "longitude" => habitation.longitude.to_f
    }
  end

  def listing_floor_size_schema(habitation)
    area = habitation.area_total_m2.presence || habitation.area_privativa_m2.presence
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
      "url" => request.original_url
    }
  end

  def positive_integer_or_nil(value)
    integer = value.to_i
    integer.positive? ? integer : nil
  end
end
