module PublicSearch
  class FriendlyUrl
    SEGMENT_SEPARATOR = "+".freeze
    BLANK_SEGMENTS = %w[todos todas all qualquer].freeze
    TRANSACTION_TYPES = {
      "venda" => "venda",
      "comprar" => "venda",
      "aluguel" => "aluguel",
      "alugar" => "aluguel",
      "locacao" => "aluguel",
      "locação" => "aluguel"
    }.freeze

    CHARACTERISTICS = {
      "lancamento" => "lancamento",
      "na-planta" => "na_planta",
      "pronto" => "pronto",
      "pronto-para-morar" => "pronto",
      "frente-mar" => "frente_mar",
      "quadra-mar" => "quadra_mar",
      "vista-mar" => "vista_mar",
      "churrasqueira" => "churrasqueira",
      "cozinha-gourmet-churrasqueira" => "cozinha_gourmet_churrasqueira",
      "mobiliado" => "mobiliado",
      "sacada" => "sacada",
      "decorado" => "decorado",
      "closet" => "closet",
      "semi-mobiliado" => "semi_mobiliado",
      "lavabo" => "lavabo",
      "lavanderia" => "lavanderia",
      "dependencia-empregada" => "dependencia_empregada",
      "dependencia-de-empregada" => "dependencia_empregada",
      "hidromassagem" => "hidromassagem",
      "piscina" => "piscina",
      "sala-estar" => "sala_estar",
      "sala-de-estar" => "sala_estar",
      "sala-jantar" => "sala_jantar",
      "sala-de-jantar" => "sala_jantar",
      "sol-manha" => "sol_manha",
      "sol-da-manha" => "sol_manha",
      "sol-tarde" => "sol_tarde",
      "sol-da-tarde" => "sol_tarde",
      "sol-dia-todo" => "sol_dia_todo",
      "sol-o-dia-todo" => "sol_dia_todo",
      "varanda" => "varanda",
      "opportunity" => "opportunity",
      "oportunidade" => "opportunity",
      "ofertas" => "opportunity"
    }.freeze

    def initialize(tenant:)
      @tenant = tenant
    end

    def params_for(route_params)
      friendly_params = {}
      transaction_type = transaction_for(route_params[:friendly_transaction])
      friendly_params[:transaction_type] = transaction_type if transaction_type.present?

      categories = values_for(route_params[:friendly_categories], lookup: category_lookup, fallback: :titleize)
      friendly_params[:category] = categories if categories.any?

      locations = values_for(route_params[:friendly_locations], lookup: location_lookup, fallback: :location)
      friendly_params[:city] = locations if locations.any?

      characteristics = values_for(route_params[:friendly_characteristics], lookup: CHARACTERISTICS, fallback: nil)
      friendly_params[:characteristics] = characteristics if characteristics.any?

      friendly_params
    end

    def self.slug_for(value)
      I18n.transliterate(value.to_s).downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-+\z/, "")
    end

    private

    attr_reader :tenant

    def transaction_for(value)
      TRANSACTION_TYPES[normalize_slug(value)]
    end

    def values_for(segment, lookup:, fallback:)
      split_segment(segment).filter_map do |slug|
        next if blank_segment?(slug)

        lookup[slug] || fallback_value(slug, fallback)
      end.uniq
    end

    def split_segment(segment)
      segment.to_s.split(SEGMENT_SEPARATOR).map { |value| normalize_slug(value) }.reject(&:blank?)
    end

    def normalize_slug(value)
      self.class.slug_for(value)
    end

    def blank_segment?(slug)
      BLANK_SEGMENTS.include?(slug)
    end

    def fallback_value(slug, fallback)
      case fallback
      when :titleize
        slug.tr("-", " ").titleize
      when :location
        slug.tr("-", " ")
      end
    end

    def category_lookup
      @category_lookup ||= property_types.index_by { |value| self.class.slug_for(value) }
    end

    def location_lookup
      @location_lookup ||= location_options.index_by { |value| self.class.slug_for(value) }
    end

    def property_types
      tenant.habitations.public_property_types
    end

    def location_options
      tenant.habitations.public_location_options.map { |option| option[:value].to_s }
    end
  end
end
