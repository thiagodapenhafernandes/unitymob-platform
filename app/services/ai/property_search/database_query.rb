module Ai
  module PropertySearch
    class DatabaseQuery
      Result = Data.define(:records, :flexible, :applied_filters)

      def initialize(tenant:, admin_user:, setting:, filters:, sort: nil, allow_flexible: true)
        @tenant = tenant
        @admin_user = admin_user
        @setting = setting
        @development_codes = Array(filters.to_h.stringify_keys["_development_codes"]).compact_blank.first(10)
        @filters = FilterContract.new(setting).normalize(filters)
        @sort = sort.to_s.presence_in(PropertySetting::AI_PROPERTY_SEARCH_SORTS) || setting.ai_property_search_default_sort
        @allow_flexible = allow_flexible
      end

      def call
        records = execute(@filters)
        return Result.new(records:, flexible: false, applied_filters: @filters) if records.any?
        return Result.new(records:, flexible: false, applied_filters: @filters) unless flexible_price_search?

        flexible_filters = @filters.merge(
          "price_max" => (@filters.fetch("price_max") * (1 + @setting.ai_property_search_price_tolerance_percentage.to_f / 100)).round(2)
        )
        Result.new(records: execute(flexible_filters), flexible: true, applied_filters: flexible_filters)
      end

      private

      def execute(filters)
        query = apply_filters(accessible_scope, filters)
        apply_sort(query).limit(@setting.ai_property_search_max_results).to_a
      end

      def accessible_scope
        # O catálogo permite que corretores consultem todos os imóveis publicáveis
        # do tenant. Edição e dados sensíveis continuam protegidos nos endpoints próprios.
        @tenant.habitations.active
      end

      def apply_filters(query, filters)
        query = query.for_sale if filters["transaction_type"] == "sale"
        query = query.for_rent if filters["transaction_type"] == "rent"
        query = query.by_category(filters["property_type"]) if filters["property_type"].present?
        query = query.by_neighborhood(filters["neighborhood"]) if filters["neighborhood"].present?
        query = query.with_min_bedrooms(filters["bedrooms_min"]) if filters["bedrooms_min"]
        query = query.with_min_suites(filters["suites_min"]) if filters["suites_min"]
        query = query.with_min_bathrooms(filters["bathrooms_min"]) if filters["bathrooms_min"]
        query = query.with_min_parking(filters["parking_spaces_min"]) if filters["parking_spaces_min"]
        query = query.where("habitations.area_privativa_m2 >= ?", filters["private_area_min"]) if filters["private_area_min"]
        query = query.where("habitations.area_privativa_m2 <= ?", filters["private_area_max"]) if filters["private_area_max"]
        query = query.where("habitations.area_total_m2 >= ?", filters["total_area_min"]) if filters["total_area_min"]
        query = query.where("habitations.area_total_m2 <= ?", filters["total_area_max"]) if filters["total_area_max"]
        query = apply_location(query, filters)
        query = apply_money(query, filters)
        query = query.where("habitations.codigo ILIKE ?", filters["property_code"]) if filters["property_code"].present?
        Array(filters["amenities"]).each do |amenity|
          query = Habitations::AmenityFilter.call(query, amenity)
        end
        query
      end

      def apply_location(query, filters)
        if filters["city"].present?
          query = query.left_outer_joins(:address).where(
            "unaccent(COALESCE(addresses.cidade, habitations.cidade, '')) ILIKE unaccent(?)",
            "%#{filters['city']}%"
          )
        end
        if @development_codes.any?
          query = query.where(codigo_empreendimento: @development_codes)
        elsif filters["development_name"].present?
          query = query.where("unaccent(COALESCE(habitations.nome_empreendimento, '')) ILIKE unaccent(?)", "%#{filters['development_name']}%")
        end
        query = query.where("unaccent(COALESCE(habitations.construtora, '')) ILIKE unaccent(?)", "%#{filters['developer_name']}%") if filters["developer_name"].present?
        query = query.where(lancamento_flag: true) if filters["property_condition"] == "launch"
        query
      end

      def apply_money(query, filters)
        price_column = filters["transaction_type"] == "rent" ? "valor_locacao_cents" : "valor_venda_cents"
        query = query.where("habitations.#{price_column} >= ?", (filters["price_min"] * 100).round) if filters["price_min"]
        query = query.where("habitations.#{price_column} <= ?", (filters["price_max"] * 100).round) if filters["price_max"]
        query = query.where("habitations.valor_condominio_cents <= ?", (filters["condominium_fee_max"] * 100).round) if filters["condominium_fee_max"]
        query = query.where("habitations.valor_iptu_cents <= ?", (filters["property_tax_max"] * 100).round) if filters["property_tax_max"]
        query
      end

      def apply_sort(query)
        case @sort
        when "price_asc" then query.order(Arel.sql("COALESCE(NULLIF(valor_venda_cents, 0), valor_locacao_cents) ASC NULLS LAST"))
        when "price_desc" then query.order(Arel.sql("COALESCE(NULLIF(valor_venda_cents, 0), valor_locacao_cents) DESC NULLS LAST"))
        when "area_desc" then query.order(area_privativa_m2: :desc)
        else query.order(data_atualizacao_crm: :desc, updated_at: :desc)
        end
      end

      def flexible_price_search?
        @allow_flexible && @setting.ai_property_search_allow_flexible_results? && @filters["price_max"].to_f.positive? &&
          @setting.ai_property_search_price_tolerance_percentage.to_i.positive?
      end
    end
  end
end
