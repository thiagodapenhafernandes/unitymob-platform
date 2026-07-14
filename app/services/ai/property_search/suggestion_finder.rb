module Ai
  module PropertySearch
    # Cascata de relaxamento quando a busca estrita não encontra nada.
    # Invariante: nenhuma variante remove cidade, tipo de imóvel ou finalidade
    # (transaction_type) — decisão de produto. Preço só flexibiliza dentro da
    # tolerância configurada (para mais no máximo, para menos no mínimo).
    class SuggestionFinder
      Result = Data.define(:records, :message, :filters, :relaxed)

      def initialize(tenant:, admin_user:, setting:, filters:, sort: nil)
        @tenant = tenant
        @admin_user = admin_user
        @setting = setting
        @filters = filters.to_h.stringify_keys
        @sort = sort
      end

      def call
        variants.each do |variant|
          result = DatabaseQuery.new(
            tenant: @tenant,
            admin_user: @admin_user,
            setting: @setting,
            filters: variant.fetch(:filters),
            sort: @sort
          ).call
          if result.records.any?
            return Result.new(
              records: result.records,
              message: variant.fetch(:message),
              filters: result.applied_filters,
              relaxed: variant.fetch(:relaxed)
            )
          end
        end
        Result.new(records: [], message: nil, filters: {}, relaxed: [])
      end

      private

      def variants
        candidates = []
        candidates.concat(flexible_variants) if @setting.ai_property_search_allow_flexible_results?
        candidates << resilient_variant if resilient_enabled?
        candidates.compact.uniq { |candidate| candidate[:filters] }.first(7)
      end

      def flexible_variants
        candidates = []
        without_characteristics = @filters.except("amenities", "property_condition")
        candidates << variant(without_characteristics, "Não encontrei correspondência com todas as características. Estas opções mantêm localização, tipo e faixa principal.", %w[amenities]) if without_characteristics != @filters

        without_development = @filters.except("development_name", "developer_name", "_development_codes")
        candidates << variant(without_development, "Não encontrei unidades no empreendimento informado. Estas opções mantêm os demais critérios na mesma região.", %w[development]) if without_development != @filters

        without_neighborhood = @filters.except("neighborhood")
        candidates << variant(without_neighborhood, "Não encontrei imóveis nesse bairro. Estas opções mantêm os demais critérios na mesma cidade.", %w[neighborhood]) if @filters["neighborhood"].present?

        reduced_quantities = reduce_quantities(@filters)
        candidates << variant(reduced_quantities, "Não houve correspondência exata. Estas opções flexibilizam em uma unidade quartos, suítes, banheiros ou vagas.", %w[quantities]) if reduced_quantities != @filters

        adjusted_price = adjust_price(@filters)
        candidates << variant(adjusted_price, "Não encontrei imóveis na faixa informada. Estas opções ficam até #{price_tolerance}% além da faixa de valor.", %w[price]) if adjusted_price

        candidates
      end

      # Variante terminal: relaxa tudo que é permitido de uma vez, mantendo
      # cidade, tipo e finalidade. É o último recurso antes de "não encontrei".
      def resilient_variant
        relaxed = []
        filters = @filters.except("amenities", "property_condition")
        relaxed << "amenities" if filters != @filters

        without_development = filters.except("development_name", "developer_name", "_development_codes")
        relaxed << "development" if without_development != filters
        filters = without_development

        if filters["neighborhood"].present?
          filters = filters.except("neighborhood")
          relaxed << "neighborhood"
        end

        reduced = reduce_quantities(filters)
        relaxed << "quantities" if reduced != filters
        filters = reduced

        adjusted = adjust_price(filters)
        if adjusted
          filters = adjusted
          relaxed << "price"
        end

        return nil if relaxed.empty?

        variant(filters, "Não encontrei correspondência exata. Estas opções mantêm cidade, tipo e finalidade, flexibilizando os demais critérios.", relaxed)
      end

      def reduce_quantities(filters)
        reduced = filters.dup
        %w[bedrooms_min parking_spaces_min suites_min bathrooms_min].each do |key|
          reduced[key] = [reduced[key].to_i - 1, 0].max if reduced[key].to_i.positive?
        end
        reduced
      end

      def adjust_price(filters)
        return nil unless price_tolerance.positive?

        adjusted = filters.dup
        changed = false
        if adjusted["price_max"].to_f.positive?
          adjusted["price_max"] = (adjusted["price_max"].to_f * (1 + price_tolerance / 100.0)).round(2)
          changed = true
        end
        if adjusted["price_min"].to_f.positive?
          adjusted["price_min"] = (adjusted["price_min"].to_f * (1 - price_tolerance / 100.0)).round(2)
          changed = true
        end
        changed ? adjusted : nil
      end

      def price_tolerance
        @setting.ai_property_search_price_tolerance_percentage.to_i
      end

      def resilient_enabled?
        @setting.respond_to?(:ai_property_search_resilient_search_enabled?) &&
          @setting.ai_property_search_resilient_search_enabled?
      end

      def variant(filters, message, relaxed)
        { filters: filters, message: message, relaxed: relaxed }
      end
    end
  end
end
