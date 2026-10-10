module PublicListingSearch
  extend ActiveSupport::Concern

  PUBLIC_LISTING_PER_PAGE = 12
  MAX_PUBLIC_LISTING_PAGE = ENV.fetch("PUBLIC_LISTING_MAX_PAGE", 50).to_i
  # Includes idênticos para toda grade pública (listagem geral e página do corretor).
  # Manter num único lugar: preload aninhado só falha com dado real, então
  # divergência aqui passa em teste sem empreendimento e quebra em produção.
  PUBLIC_LISTING_INCLUDES = [
    :address,
    { constructor: { logo_attachment: :blob } },
    { empreendimento: { constructor: { logo_attachment: :blob } } }
  ].freeze

  private

  def search_params
    permitted = params.permit(
      :page,
      :seo_slug,
      :transaction_type,
      :finalidade,
      :category,
      :tipo,
      :city,
      :cidade,
      :neighborhood,
      :development,
      :empreendimento,
      :constructor,
      :state,
      :min_bedrooms,
      :min_suites,
      :min_bathrooms,
      :min_parking,
      :bedrooms,
      :suites,
      :parking,
      :bathrooms,
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
      development: [],
      empreendimento: [],
      characteristics: [],
      bedrooms: [],
      suites: [],
      parking: [],
      bathrooms: []
    )
    permitted.delete(:page)
    permitted.delete(:seo_slug)

    permitted[:transaction_type] = normalize_transaction_type(permitted[:transaction_type].presence || permitted[:finalidade])
    permitted[:category] = permitted[:category].presence || permitted[:tipo]
    permitted[:city] = permitted[:city].presence || permitted[:cidade]
    apply_price_range_params(permitted)

    category_values = normalize_filter_values(permitted[:category])
    permitted[:category] = category_values if category_values.any?

    city_values = normalize_filter_values(permitted[:city])
    permitted[:city] = city_values if city_values.any?

    development_values = normalize_filter_values(permitted[:development].presence || permitted[:empreendimento])
    permitted[:development] = development_values if development_values.any?

    permitted
  end

  def apply_price_range_params(permitted)
    return if permitted[:price_range].blank?

    price_range = permitted[:price_range].to_s.strip
    unless price_range.match?(/\A\d{1,12}(?:-\d{1,12})?\z/)
      permitted[:price_range] = nil
      return
    end

    min_price, max_price = price_range.split("-", 2)
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
    when ActionController::Parameters
      normalize_filter_values(value.to_unsafe_h)
    when Hash
      value.sort_by { |key, _| key.to_s }.flat_map { |_, item| normalize_filter_values(item) }.reject(&:blank?).uniq
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

  def cached_listing_total_entries(scope, filters, namespace: nil)
    key_filters = namespace ? filters.merge("_listing_namespace" => namespace) : filters
    Rails.cache.fetch(Habitation.public_listing_count_cache_key(public_tenant.id, key_filters), expires_in: 15.minutes) do
      scope.count
    end
  end
end
