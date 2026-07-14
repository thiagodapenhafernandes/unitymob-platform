module Ai
  module PropertySearch
    class DevelopmentResolver
      Result = Data.define(:filters, :candidates, :match_type) do
        def ambiguous? = candidates.many?
        def resolved? = candidates.one?
      end

      NORMALIZED_NAME_SQL = "regexp_replace(unaccent(lower(COALESCE(habitations.nome_empreendimento, habitations.titulo_anuncio, ''))), '[^a-z0-9]+', ' ', 'g')".freeze

      def initialize(tenant:, setting:, filters:)
        @tenant = tenant
        @setting = setting
        @filters = filters.stringify_keys
      end

      def call
        return Result.new(filters: @filters, candidates: [], match_type: nil) unless resolution_requested?

        records, match_type = resolve
        options = records.first(6).map { |record| option(record) }
        resolved_filters = @filters
        if records.any?
          record = records.first
          resolved_filters = @filters.merge(
            "development_name" => records.one? ? display_name(record) : @filters["development_name"],
            "_development_codes" => records.filter_map(&:codigo).first(10)
          )
        end
        Result.new(filters: resolved_filters, candidates: options, match_type: match_type)
      end

      private

      def resolution_requested?
        (@setting.ai_property_search_development_name_enabled? && @filters["development_name"].present?) ||
          (@setting.ai_property_search_developer_name_enabled? && @filters["developer_name"].present?) ||
          characteristic_lookup?
      end

      def resolve
        term = DevelopmentAlias.normalize(@filters["development_name"])
        base = constrained_scope
        return characteristics_match(base) if term.blank?

        exact = base.where("#{NORMALIZED_NAME_SQL} = ?", term).limit(7).to_a
        return [exact, "exact"] if exact.any?

        if @setting.ai_property_search_development_aliases_enabled?
          alias_ids = DevelopmentAlias.where(tenant: @tenant)
            .where("normalized_name = ? OR normalized_name LIKE ?", term, "%#{DevelopmentAlias.sanitize_sql_like(term)}%")
            .limit(7).pluck(:development_id)
          aliased = base.where(id: alias_ids).limit(7).to_a
          return [aliased, "alias"] if aliased.any?
        end

        partial = base.where("#{NORMALIZED_NAME_SQL} LIKE ?", "%#{Habitation.sanitize_sql_like(term)}%").limit(7).to_a
        return [partial, "partial"] if partial.any?

        if @setting.ai_property_search_fuzzy_matching_enabled?
          threshold = @setting.ai_property_search_fuzzy_similarity_threshold.to_f
          fuzzy = base.where("similarity(#{NORMALIZED_NAME_SQL}, ?) >= ?", term, threshold)
            .order(Arel.sql(Habitation.sanitize_sql_array(["similarity(#{NORMALIZED_NAME_SQL}, ?) DESC", term])))
            .limit(7).to_a
          return [fuzzy, "fuzzy"] if fuzzy.any?
        end

        characteristics_match(base)
      end

      def constrained_scope
        scope = @tenant.habitations.where(tipo: "Empreendimento")
        if @setting.ai_property_search_developer_name_enabled? && @filters["developer_name"].present?
          scope = scope.where("unaccent(lower(COALESCE(habitations.construtora, ''))) ILIKE unaccent(lower(?))", "%#{@filters['developer_name']}%")
        end
        scope = scope.by_neighborhood(@filters["neighborhood"]) if @filters["neighborhood"].present?
        if @filters["city"].present?
          scope = scope.left_outer_joins(:address).where("unaccent(COALESCE(addresses.cidade, habitations.cidade, '')) ILIKE unaccent(?)", "%#{@filters['city']}%")
        end
        scope = scope.where(lancamento_flag: true) if @filters["property_condition"] == "launch"
        if @setting.ai_property_search_search_by_characteristics_enabled?
          Array(@filters["amenities"]).each do |feature|
            scope = scope.where("unaccent(COALESCE(habitations.searchable_features, '')) ILIKE unaccent(?)", "%#{feature}%")
          end
        end
        scope
      end

      # Cidade/bairro sozinhos NÃO disparam o lookup: sem menção a
      # empreendimento, restringir a busca a unidades de empreendimentos da
      # região excluiria imóveis avulsos que casam exatamente com o pedido.
      def characteristic_lookup?
        return false unless @setting.ai_property_search_search_by_characteristics_enabled?

        @filters.values_at("developer_name", "property_condition").any?(&:present?) || Array(@filters["amenities"]).any?
      end

      def characteristics_match(scope)
        return [[], nil] unless characteristic_lookup?

        [scope.limit(7).to_a, "characteristics"]
      end

      def option(record)
        {
          id: record.id,
          name: display_name(record),
          developer_name: record.constructor_name,
          neighborhood: record.address&.bairro.presence || record.bairro,
          city: record.address&.cidade.presence || record.cidade,
          match_type: nil
        }.compact
      end

      def display_name(record)
        record.nome_empreendimento.presence || record.titulo_anuncio.presence || record.codigo
      end
    end
  end
end
