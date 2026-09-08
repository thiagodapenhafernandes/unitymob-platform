module BrowserExtension
  # Receives the already authorized commercial scope; filters can only narrow it.
  class PropertyCatalog
    include HabitationQuickFilters
    SORT_KEYS = %w[activity code category address number complement bedrooms sale_price rental_price neighborhood title rental_m2 sale_m2 rental_total].zip(HabitationCatalogSort::SORT_OPTIONS.keys).to_h.freeze
    RANGES = { bedrooms: :dormitorios_qtd, suites: :suites_qtd, bathrooms: :banheiros_qtd, parking: :vagas_qtd,
      area_total: :area_total_m2, area: :area_privativa_m2 }.freeze
    OPTIONS = {category: :categoria, development: :nome_empreendimento, status: :status,
      situation: :situacao, keys: :key_location}.freeze
    BOOLEANS = {exchange: :aceita_permuta_flag, installments: :aceita_parcelamento_flag, rental_management: :rental_management_flag}.freeze

    def initialize(scope:, user:, params:)
      @base, @user, @params = scope, user, params
    end

    def call
      purpose = text(:purpose).presence || "all"
      facet = text(:facet).presence || "all"
      raise ArgumentError unless %w[all venda locacao].include?(purpose) && %w[all mine venda locacao opportunity].include?(facet)
      scope = facet_scope(@base, facet)
      scope = scope.for_sale if purpose == "venda"
      scope = scope.for_rent if purpose == "locacao"
      query = text(:q)
      scope = query.match?(/\A\d+\z/) ? scope.where("habitations.codigo::text LIKE ?", "#{query}%") : scope.admin_search_text(query) if query.present?
      scope = scope.where(codigo: text(:reference)) if text(:reference).present?
      scope = scope.by_category(values(:category)) if values(:category).any?
      OPTIONS.except(:category).each { |key, column| scope = scope.where(column => values(key)) if values(key).any? }
      if values(:owner).any?
        ids = values(:owner)
        raise ArgumentError unless ids.all? { |id| id.match?(/\A\d+\z/) }
        scope = assigned_to(scope, ids)
      end
      scope = scope.left_outer_joins(:address)
      {city: :cidade, neighborhood: :bairro_comercial, address: :logradouro, number: :numero}.each do |key, column|
        next if values(key).empty?
        legacy = key == :address ? :endereco : column
        expression = "COALESCE(NULLIF(TRIM(addresses.#{column}), ''), habitations.#{legacy})"
        predicates = values(key).map { "unaccent(#{expression}) ILIKE unaccent(?)" }.join(" OR ")
        scope = scope.where(predicates, *values(key).map { |v| "%#{ActiveRecord::Base.sanitize_sql_like(v)}%" })
      end
      values(:quick).each do |quick|
        raise ArgumentError unless HabitationQuickFilters::QUICK_FILTERS.key?(quick)
        scope = apply_quick_scope_filter(scope, quick)
      end
      values(:amenities).each { |amenity| scope = Habitations::AmenityFilter.call(scope, amenity) }
      BOOLEANS.each do |key, column|
        next if text(key).blank?
        raise ArgumentError unless %w[0 1].include?(text(key))
        scope = scope.where(column => (text(key) == "1"))
      end
      values(:exchange_type).each do |kind|
        column = {"vehicle" => :aceita_permuta_veiculo_flag, "property" => :aceita_permuta_imovel_flag, "others" => :aceita_permuta_outros_flag}.fetch(kind) { raise ArgumentError }
        scope = scope.where(column => true)
      end
      if text(:promotion).present?
        raise ArgumentError unless %w[0 1].include?(text(:promotion))
        sql = "((COALESCE(valor_venda_anterior_cents, 0) > COALESCE(valor_venda_cents, 0) AND COALESCE(valor_venda_cents, 0) > 0) OR (COALESCE(valor_locacao_anterior_cents, 0) > COALESCE(valor_locacao_cents, 0) AND COALESCE(valor_locacao_cents, 0) > 0))"
        scope = scope.where(text(:promotion) == "1" ? sql : "NOT #{sql}")
      end
      RANGES.each do |key, column|
        scope = range(scope, "habitations.#{column}", number("#{key}_min") || number(key), number("#{key}_max"))
      end
      minimum, maximum = number(:min_price), number(:max_price)
      price = purpose == "locacao" || facet == "locacao" ? "habitations.valor_locacao_cents" : purpose == "venda" || facet == "venda" ? "habitations.valor_venda_cents" : "COALESCE(NULLIF(habitations.valor_venda_cents, 0), habitations.valor_locacao_cents)"
      scope = range(scope, price, minimum && minimum * 100, maximum && maximum * 100)
      sort = HabitationCatalogSort::SORT_OPTIONS.fetch(SORT_KEYS.fetch(text(:order).presence || "activity") { raise ArgumentError })
      direction = text(:direction).presence || sort[:default_direction]
      raise ArgumentError unless %w[asc desc].include?(direction)
      column = sort[:column].include?("(") ? sort[:column] : "habitations.#{sort[:column]}"
      scope.reorder(Arel.sql("#{column} #{direction} NULLS LAST, habitations.id DESC"))
    end

    def counts
      %w[all mine venda locacao opportunity].to_h { |facet| [facet, facet_scope(@base, facet).count] }
    end

    def options
      result = OPTIONS.to_h { |key, column| [key, @base.where.not(column => [nil, ""]).distinct.order(column).pluck(column)] }
      result[:city] = address_options(:cidade)
      result[:neighborhood] = address_options(:bairro_comercial)
      {amenity_features: "feature", amenity_infrastructure: "infrastructure"}.each do |key, category|
        names = @user.tenant.attribute_options.where(context: "habitation", category: category).pluck(:name)
        normalizer = AttributeOptions::HabitationFeatureNormalizer
        result[key] = names.filter_map { |name| normalizer.label(name, category: "infrastructure") }
                           .index_by { |name| normalizer.key(name) }.values.sort_by { |name| normalizer.key(name) }
      end
      # Only expose brokers assigned to an authorized property in this tenant.
      ids = @base.where.not(admin_user_id: nil).distinct.pluck(:admin_user_id)
      ids |= HabitationBrokerAssignment.where(habitation_id: @base.select(:id)).distinct.pluck(:admin_user_id)
      result[:owner] = @user.tenant.admin_users.where(id: ids).order(:name).pluck(:id, :name).map { |id, name| [id.to_s, name] }
      result
    end

    private

    def text(key)
      value = @params[key].to_s.strip
      raise ArgumentError if value.length > 100
      value
    end

    def values(key)
      value = Array(@params[key]).map { |v| v.to_s.strip }.reject(&:empty?).uniq
      raise ArgumentError if value.length > 30 || value.any? { |v| v.length > 100 }
      value
    end

    def number(key)
      value = text(key)
      return if value.empty?
      raise ArgumentError unless value.match?(/\A\d{1,12}(?:\.\d{1,2})?\z/)
      value.to_d
    end

    def range(scope, column, minimum, maximum)
      raise ArgumentError if minimum && maximum && minimum > maximum
      scope = scope.where("#{column} >= ?", minimum) if minimum
      scope = scope.where("#{column} <= ?", maximum) if maximum
      scope
    end

    def assigned_to(scope, ids)
      scope.where("habitations.admin_user_id IN (:ids) OR EXISTS (SELECT 1 FROM habitation_broker_assignments a WHERE a.habitation_id = habitations.id AND a.admin_user_id IN (:ids))", ids: ids)
    end

    def facet_scope(scope, facet)
      case facet
      when "mine" then assigned_to(scope, [@user.id])
      when "venda" then scope.for_sale
      when "locacao" then scope.for_rent
      when "opportunity" then scope.opportunity
      else scope
      end
    end

    def address_options(column)
      expression = "COALESCE(NULLIF(TRIM(addresses.#{column}), ''), habitations.#{column})"
      @base.left_outer_joins(:address).distinct.pluck(Arel.sql(expression)).compact_blank.sort
    end
  end
end
