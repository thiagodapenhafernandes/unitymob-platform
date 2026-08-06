module Ai
  module PropertySearch
    class SpecificRequest
      Result = Data.define(:filters, :exact)
      NORMALIZED_DEVELOPMENT_SQL = "regexp_replace(unaccent(lower(COALESCE(NULLIF(habitations.nome_empreendimento, ''), habitations.titulo_anuncio, ''))), '[^a-z0-9]+', ' ', 'g')".freeze

      CODE_PATTERN = /
        \b(?:c[oó]d(?:igo)?|ref(?:er[êe]ncia)?)\b
        (?:\s+(?:do|da|de|o|a|im[oó]vel|refer[êe]ncia|ref))*\s*
        (?:[:#-]\s*)?
        (?<code>[a-z0-9][a-z0-9._-]{1,30})
      /ix.freeze
      SINGLE_CODE_PATTERN = /\A#?(?<code>[a-z]*\d{3,}[a-z0-9._-]*)\z/i.freeze
      DEVELOPMENT_PATTERN = /
        \b(?:empreendimento|edif[ií]cio|pr[eé]dio|condom[ií]nio|residencial)\b
        \s+(?<name>.+)
      /ix.freeze
      NAME_BOUNDARY = /
        \s+\b(?:com|em|no|na|para|por|entre|at[eé]|quartos?|su[ií]tes?|vagas?|frente|valor|pre[cç]o|alugar|comprar|venda|loca[cç][aã]o)\b
      /ix.freeze
      LEADING_NAME_NOISE = /\A(?:chamad[oa]|nome|do|da|de|o|a)\s+/i.freeze
      INVALID_NAME_START = /\A(?:at[eé]|valor|pre[cç]o|taxa|\d)/i.freeze
      BARE_DEVELOPMENT_HINT = /
        \b(?:residence|residencial|tower|towers|garden|gardens|palace|place|park|beach|view|village|royal|diamond|plaza|square|mare|bay|sky|skyline)\b
      /ix.freeze
      GENERIC_SEARCH_PHRASE = /
        \b(?:frente\s+(?:ao\s+)?mar|vista\s+(?:para\s+o\s+)?mar|alto\s+padr[aã]o|pre[cç]o\s+reduzido)\b
      /ix.freeze

      def initialize(setting:, text:, interpreted_filters: {}, tenant: nil)
        @setting = setting
        @tenant = tenant || setting.tenant
        @text = text.to_s.strip
        @interpreted_filters = interpreted_filters
        @contract = FilterContract.new(setting)
      end

      def call
        code = property_code
        return exact_result("property_code" => code) if code.present?

        interpreted = @contract.normalize(@interpreted_filters)
        development = development_name
        if development.present?
          catalog_development = catalog_development_name(development, explicit: true)
          return exact_result(specific_development_filters(catalog_development.presence || development, interpreted))
        end

        catalog_development = catalog_development_name
        return exact_result(specific_development_filters(catalog_development, interpreted)) if catalog_development.present?

        return exact_result("property_code" => interpreted["property_code"]) if interpreted["property_code"].present?
        return exact_result(specific_development_filters(interpreted["development_name"], interpreted)) if interpreted["development_name"].present?

        bare_development = bare_development_name
        return exact_result(specific_development_filters(bare_development, interpreted)) if bare_development.present?

        Result.new(filters: interpreted, exact: false)
      end

      private

      def exact_result(filters)
        normalized = @contract.normalize(filters)
        return Result.new(filters: @contract.normalize(@interpreted_filters), exact: false) if normalized.empty?

        Result.new(filters: normalized, exact: true)
      end

      def property_code
        explicit_code = @text.match(CODE_PATTERN)&.[](:code)
        return clean_code(explicit_code) if explicit_code.to_s.match?(/\d/)

        clean_code(@text.match(SINGLE_CODE_PATTERN)&.[](:code))
      end

      def clean_code(value)
        value.to_s.strip.delete_prefix("#").presence
      end

      def development_name
        raw_name = @text.match(DEVELOPMENT_PATTERN)&.[](:name)
        clean_name(raw_name)
      end

      def clean_name(value)
        name = value.to_s.strip
        name = name.split(NAME_BOUNDARY).first.to_s.strip
        name = name.gsub(/[.,;:!?]\z/, "").strip
        name = name.gsub(LEADING_NAME_NOISE, "").strip while name.match?(LEADING_NAME_NOISE)
        return if name.blank? || name.match?(INVALID_NAME_START)

        name.first(120)
      end

      def bare_development_name
        name = clean_name(@text)
        normalized = DevelopmentAlias.normalize(name)
        return if normalized.blank? || normalized.split.size > 6
        return unless normalized.match?(BARE_DEVELOPMENT_HINT)

        name
      end

      def specific_development_filters(development, interpreted = @contract.normalize(@interpreted_filters))
        filters = { "development_name" => development }
        filters.merge(evidence_supported_filters(interpreted))
      end

      def evidence_supported_filters(interpreted)
        normalized_text = DevelopmentAlias.normalize(@text)
        interpreted.each_with_object({}) do |(key, value), filters|
          filters[key] = value if filter_supported_by_text?(key, value, normalized_text)
        end
      end

      def filter_supported_by_text?(key, value, normalized_text)
        case key
        when "transaction_type"
          normalized_text.match?(/\b(comprar|compra|venda|vender|alugar|aluguel|locacao|locar)\b/)
        when "property_type"
          normalized_text.match?(/\b(apartamento|apartamentos|apto|casa|casas|cobertura|terreno|sala|comercial)\b/)
        when "property_condition"
          normalized_text.match?(/\b(lancamento|planta|pronto|novo|obra|construcao)\b/)
        when "bedrooms_min"
          normalized_text.match?(/\b(dormitorio|dormitorios|quarto|quartos)\b/)
        when "suites_min"
          normalized_text.match?(/\b(suite|suites)\b/)
        when "bathrooms_min"
          normalized_text.match?(/\b(banheiro|banheiros)\b/)
        when "parking_spaces_min"
          normalized_text.match?(/\b(vaga|vagas|garagem)\b/)
        when "private_area_min", "private_area_max", "total_area_min", "total_area_max"
          normalized_text.match?(/\b(area|m2|metro|metros)\b/)
        when "price_min", "price_max"
          normalized_text.match?(/\b(valor|preco|reais|mil|milhao|milhoes|mi|milhoes)\b/) || normalized_text.match?(/\d/)
        when "condominium_fee_max"
          normalized_text.match?(/\b(condominio|taxa)\b/)
        when "property_tax_max"
          normalized_text.match?(/\b(iptu)\b/)
        when "amenities"
          Array(value).any? { |amenity| normalized_text.include?(DevelopmentAlias.normalize(amenity)) }
        else
          false
        end
      end

      def catalog_development_name(term = nil, explicit: false)
        return unless development_lookup_enabled?

        term = clean_name(term.presence || @text)
        normalized = DevelopmentAlias.normalize(term)
        return if normalized.length < 3
        return if !explicit && generic_search_phrase?(normalized)

        exact_name = unique_catalog_development_name(
          development_catalog_scope.where("#{NORMALIZED_DEVELOPMENT_SQL} = ?", normalized).limit(20)
        )
        return exact_name if exact_name.present?

        if normalized.length >= 4
          partial_name = unique_catalog_development_name(
            development_catalog_scope.where(
              "#{NORMALIZED_DEVELOPMENT_SQL} LIKE ?",
              "%#{ActiveRecord::Base.sanitize_sql_like(normalized)}%"
            ).limit(20)
          )
          return partial_name if partial_name.present?
        end

        return unless @setting.ai_property_search_fuzzy_matching_enabled?

        threshold = [@setting.ai_property_search_fuzzy_similarity_threshold.to_f, 0.55].max
        unique_catalog_development_name(
          development_catalog_scope
            .where("similarity(#{NORMALIZED_DEVELOPMENT_SQL}, ?) >= ?", normalized, threshold)
            .order(Arel.sql(Habitation.sanitize_sql_array(["similarity(#{NORMALIZED_DEVELOPMENT_SQL}, ?) DESC", normalized])))
            .limit(20)
        )
      rescue StandardError
        nil
      end

      def development_lookup_enabled?
        @tenant.present? &&
          @setting.ai_property_search_development_name_enabled? &&
          Array(@setting.ai_property_search_allowed_fields).map(&:to_s).include?("development")
      end

      def generic_search_phrase?(normalized)
        normalized.match?(GENERIC_SEARCH_PHRASE)
      end

      def development_catalog_scope
        @tenant.habitations.publicly_listable
          .where("NULLIF(BTRIM(COALESCE(habitations.nome_empreendimento, habitations.titulo_anuncio, '')), '') IS NOT NULL")
      end

      def unique_catalog_development_name(scope)
        names = scope.pluck(:nome_empreendimento, :titulo_anuncio).filter_map do |name, title|
          name.presence || title.presence
        end
        grouped = names.group_by { |name| DevelopmentAlias.normalize(name) }
        return if grouped.keys.many?

        grouped.values.first&.first
      end
    end
  end
end
