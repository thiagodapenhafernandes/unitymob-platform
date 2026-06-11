require "digest"
require "uri"

module Seo
  class PageIdentity
    TRACKED_PROPERTY_FILTERS = %w[
      transaction_type finalidade category tipo city cidade neighborhood bairro state
      min_bedrooms min_suites min_bathrooms min_parking min_area max_area min_price max_price
      price_range furnished accepts_exchange accepts_financing characteristics search
    ].freeze
    INDEXABLE_PROPERTY_FILTERS = %w[transaction_type category tipo city cidade neighborhood bairro characteristics price_range].freeze
    INDEXABLE_DEVELOPMENT_FILTERS = %w[city cidade neighborhood bairro characteristics].freeze

    IGNORED_PARAMS = /\A(utm_.*|fbclid|gclid|msclkid|_gl|commit|authenticity_token|controller|action)\z/

    attr_reader :controller

    def initialize(controller)
      @controller = controller
    end

    def to_h
      if habitations_index?
        property_listing_identity
      elsif developments_index?
        developments_listing_identity
      elsif habitation_show?
        property_show_identity
      else
        generic_identity
      end
    end

    private

    def request
      controller.request
    end

    def params
      controller.params
    end

    def habitations_index?
      controller.controller_name == "habitations" && controller.action_name == "index"
    end

    def developments_index?
      controller.controller_name == "empreendimentos" && controller.action_name == "index"
    end

    def habitation_show?
      controller.controller_name == "habitations" && controller.action_name == "show" && controller.instance_variable_get(:@habitation).present?
    end

    def property_listing_identity
      return strategic_property_listing_identity if strategic_property_page.present?

      normalized = normalized_property_filters
      digest = Digest::SHA1.hexdigest(normalized.to_json)[0, 12]
      page_name = normalized.any? ? "imoveis:#{digest}" : "imoveis"
      canonical_key = normalized.any? ? "properties_index:#{digest}" : "imoveis"
      noindex = controller.instance_variable_get(:@habitations).try(:total_entries).to_i.zero?
      indexable = !noindex && indexable_property_filters?(normalized)

      {
        canonical_key: canonical_key,
        page_name: page_name,
        page_type: "property_listing",
        canonical_path: canonical_path("/imoveis", normalized),
        normalized_params: normalized,
        robots_index: indexable,
        robots_follow: true,
        title_fallback: controller.instance_variable_get(:@page_title),
        description_fallback: controller.instance_variable_get(:@page_description),
        keywords_fallback: controller.instance_variable_get(:@page_keywords)
      }
    end

    def developments_listing_identity
      return strategic_development_listing_identity if strategic_development_page.present?

      normalized = normalized_development_filters
      digest = Digest::SHA1.hexdigest(normalized.to_json)[0, 12]
      page_name = normalized.any? ? "empreendimentos:#{digest}" : "empreendimentos"
      canonical_key = normalized.any? ? "developments_index:#{digest}" : "empreendimentos"
      noindex = controller.instance_variable_get(:@empreendimentos).try(:total_entries).to_i.zero?
      indexable = !noindex && indexable_development_filters?(normalized)

      {
        canonical_key: canonical_key,
        page_name: page_name,
        page_type: "developments_index",
        canonical_path: canonical_path("/empreendimentos", normalized),
        normalized_params: normalized,
        robots_index: indexable,
        robots_follow: true,
        title_fallback: controller.instance_variable_get(:@page_title),
        description_fallback: controller.instance_variable_get(:@page_description),
        keywords_fallback: controller.instance_variable_get(:@page_keywords)
      }
    end

    def strategic_property_listing_identity
      slug = params[:seo_slug].to_s
      landing = strategic_property_page
      noindex = controller.instance_variable_get(:@habitations).try(:total_entries).to_i.zero?

      {
        canonical_key: "properties_landing:#{slug}",
        page_name: "imoveis:#{slug}",
        page_type: "property_landing",
        canonical_path: "/imoveis/#{slug}",
        normalized_params: landing[:params],
        robots_index: !noindex,
        robots_follow: true,
        title_fallback: landing[:title],
        description_fallback: landing[:description],
        keywords_fallback: landing[:label],
        intro_fallback: Seo::StrategicLanding.property_intro(landing)
      }
    end

    def strategic_development_listing_identity
      slug = params[:seo_slug].to_s
      landing = strategic_development_page
      noindex = controller.instance_variable_get(:@empreendimentos).try(:total_entries).to_i.zero?

      {
        canonical_key: "developments_landing:#{slug}",
        page_name: "empreendimentos:#{slug}",
        page_type: "development_landing",
        canonical_path: "/empreendimentos/#{slug}",
        normalized_params: landing[:params],
        robots_index: !noindex,
        robots_follow: true,
        title_fallback: landing[:title],
        description_fallback: landing[:description],
        keywords_fallback: landing[:label],
        intro_fallback: Seo::StrategicLanding.development_intro(landing)
      }
    end

    def property_show_identity
      habitation = controller.instance_variable_get(:@habitation)
      key = habitation.codigo.presence || habitation.id

      {
        canonical_key: "property:#{key}",
        page_name: "imovel:#{key}",
        page_type: habitation.empreendimento? ? "development_show" : "property_show",
        canonical_path: request.path,
        normalized_params: {},
        robots_index: true,
        robots_follow: true,
        title_fallback: controller.instance_variable_get(:@page_title),
        description_fallback: controller.instance_variable_get(:@page_description),
        keywords_fallback: controller.instance_variable_get(:@page_keywords)
      }
    end

    def generic_identity
      normalized = normalized_generic_params
      path = request.path.presence || "/"
      digest_source = [controller.controller_name, controller.action_name, path, normalized].to_json
      digest = Digest::SHA1.hexdigest(digest_source)[0, 12]
      page_type = "#{controller.controller_name}_#{controller.action_name}"
      canonical_key = path == "/" ? "home" : "#{page_type}:#{digest}"

      {
        canonical_key: canonical_key,
        page_name: path == "/" ? "home" : "#{page_type}:#{digest}",
        page_type: page_type,
        canonical_path: canonical_path(path, normalized),
        normalized_params: normalized,
        robots_index: true,
        robots_follow: true,
        title_fallback: controller.instance_variable_get(:@page_title),
        description_fallback: controller.instance_variable_get(:@page_description),
        keywords_fallback: controller.instance_variable_get(:@page_keywords)
      }
    end

    def normalized_property_filters
      raw = params.to_unsafe_h.slice(*TRACKED_PROPERTY_FILTERS)
      normalize_hash(raw)
    end

    def normalized_development_filters
      normalize_hash(params.to_unsafe_h.slice("q", "city", "cidade", "neighborhood", "bairro", "characteristics"))
    end

    def normalized_generic_params
      normalize_hash(params.to_unsafe_h.except("id", "page").reject { |key, _| key.to_s.match?(IGNORED_PARAMS) })
    end

    def normalize_hash(hash)
      hash.each_with_object({}) do |(key, value), result|
        next if key.to_s.match?(IGNORED_PARAMS)

        normalized = normalize_value(value)
        next if normalized.blank?

        result[key.to_s] = normalized
      end.sort.to_h
    end

    def normalize_value(value)
      case value
      when Array
        value.flat_map { |item| normalize_value(item) }.reject(&:blank?).map(&:to_s).map(&:strip).sort.uniq
      when Hash, ActionController::Parameters
        normalize_hash(value.to_h)
      else
        value.to_s.strip
      end
    end

    def canonical_path(path, normalized)
      return path if normalized.blank?

      pairs = normalized.flat_map do |key, value|
        Array(value).map { |item| [key, item] }
      end
      query = URI.encode_www_form(pairs)
      "#{path}?#{query}"
    end

    def strategic_property_page
      @strategic_property_page ||= Seo::StrategicLanding.property(params[:seo_slug])
    end

    def strategic_development_page
      @strategic_development_page ||= Seo::StrategicLanding.development(params[:seo_slug])
    end

    def indexable_property_filters?(normalized)
      return true if normalized.blank?
      return false if normalized.key?("search")
      return false if (normalized.keys - INDEXABLE_PROPERTY_FILTERS).any?
      return false if normalized.keys.size > 3

      normalized.key?("city") || normalized.key?("cidade") ||
        normalized.key?("neighborhood") || normalized.key?("bairro") ||
        normalized.key?("characteristics") || normalized.key?("category") ||
        normalized.key?("tipo")
    end

    def indexable_development_filters?(normalized)
      return true if normalized.blank?
      return false if normalized.key?("q")
      return false if (normalized.keys - INDEXABLE_DEVELOPMENT_FILTERS).any?
      return false if normalized.keys.size > 2

      normalized.key?("city") || normalized.key?("cidade") ||
        normalized.key?("neighborhood") || normalized.key?("bairro") ||
        normalized.key?("characteristics")
    end

  end
end
