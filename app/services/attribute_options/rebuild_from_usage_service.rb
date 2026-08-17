# frozen_string_literal: true

require "set"

module AttributeOptions
  class RebuildFromUsageService
    CONTEXT = "habitation"
    CATEGORIES = %w[
      feature infrastructure unique_feature
      street_type city neighborhood commercial_neighborhood imediacoes
    ].freeze

    def initialize(tenant: nil, categories: nil)
      @tenant = tenant || Current.tenant
      @categories = Array(categories.presence || CATEGORIES).map(&:to_s) & CATEGORIES
      raise ArgumentError, "Tenant obrigatório para reconstruir catálogo dinâmico" if @tenant.blank?
    end

    def call
      values_by_category = {
        "feature" => extract_feature_values,
        "infrastructure" => extract_infrastructure_values,
        "unique_feature" => extract_unique_feature_values,
        "street_type" => extract_address_scalar_values(:tipo_endereco, legacy_column: :tipo_endereco),
        "city" => extract_address_scalar_values(:cidade, legacy_column: :cidade),
        "neighborhood" => extract_address_scalar_values(:bairro, legacy_column: :bairro),
        "commercial_neighborhood" => extract_address_scalar_values(:bairro_comercial, legacy_column: :bairro_comercial),
        "imediacoes" => extract_imediacoes_values
      }

      upsert_values(values_by_category.slice(*@categories))
    end

    private

    def upsert_values(values_by_category)
      now = Time.current
      rows = []

      existing = attribute_option_scope.where(context: CONTEXT, category: @categories).pluck(:category, :name)
      existing_lookup = existing.each_with_object({}) do |(category, name), acc|
        acc[[category, normalized_key(name)]] = true
      end

      values_by_category.each do |category, values|
        values.each do |value|
          key = [category, normalized_key(value)]
          next if existing_lookup[key]

          rows << {
            tenant_id: @tenant.id,
            context: CONTEXT,
            category: category,
            name: value,
            created_at: now,
            updated_at: now
          }
          existing_lookup[key] = true
        end
      end

      return 0 if rows.empty?

      AttributeOption.insert_all(
        rows,
        unique_by: :index_attribute_options_on_context_category_lower_name
      )

      rows.size
    end

    def extract_feature_values
      values = Set.new

      habitation_scope.find_each do |habitation|
        raw = habitation.caracteristicas
        items =
          case raw
          when Hash
            raw.values.presence || raw.keys
          when Array
            raw
          when String
            raw.split(/[,\n;]+/)
          else
            []
          end

        normalize_items(items, category: "feature").each { |item| values << item }
      end

      values.to_a.sort
    end

    def extract_infrastructure_values
      values = Set.new

      habitation_scope.find_each do |habitation|
        normalize_items(habitation.infra_estrutura, category: "infrastructure").each { |item| values << item }
      end

      values.to_a.sort
    end

    def extract_unique_feature_values
      values = Set.new

      habitation_scope.find_each do |habitation|
        raw = habitation.caracteristica_unica
        items =
          case raw
          when Array
            raw
          when String
            raw.split(/[,\n;]+/)
          else
            Array(raw)
          end

        normalize_items(items, category: "feature").each { |item| values << item }
      end

      values.to_a.sort
    end

    def extract_imediacoes_values
      values = Set.new

      Address.where(addressable_type: "Habitation", addressable_id: habitation_scope.select(:id)).find_each do |address|
        normalize_items(address.imediacoes, category: "feature").each { |item| values << item }
      end

      values.to_a.sort
    end

    def extract_address_scalar_values(attribute, legacy_column: nil)
      values = Set.new

      Address.where(addressable_type: "Habitation", addressable_id: habitation_scope.select(:id)).pluck(attribute).each do |value|
        normalized = value.to_s.squish
        values << normalized if normalized.present?
      end

      if legacy_column.present? && Habitation.column_names.include?(legacy_column.to_s)
        habitation_scope.where.not(legacy_column => [nil, ""]).pluck(legacy_column).each do |value|
          normalized = value.to_s.squish
          values << normalized if normalized.present?
        end
      end

      values.to_a.sort
    end

    def normalize_items(raw, category:)
      case raw
      when Array
        raw
      when Hash
        raw.values
      when String
        raw.split(/[,\n;]+/)
      else
        Array(raw)
      end.map { |item| AttributeOptions::HabitationFeatureNormalizer.label(item, category: category) }
       .reject(&:blank?)
       .uniq
    end

    def normalized_key(value)
      AttributeOptions::HabitationFeatureNormalizer.key(value)
    end

    def habitation_scope
      @tenant.habitations
    end

    def attribute_option_scope
      @tenant.attribute_options
    end
  end
end
