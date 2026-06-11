# frozen_string_literal: true

require "set"

module AttributeOptions
  class RebuildFromUsageService
    CONTEXT = "habitation"
    CATEGORIES = %w[feature infrastructure unique_feature imediacoes].freeze

    def call
      values_by_category = {
        "feature" => extract_feature_values,
        "infrastructure" => extract_infrastructure_values,
        "unique_feature" => extract_unique_feature_values,
        "imediacoes" => extract_imediacoes_values
      }

      upsert_values(values_by_category)
    end

    private

    def upsert_values(values_by_category)
      now = Time.current
      rows = []

      existing = AttributeOption.where(context: CONTEXT, category: CATEGORIES).pluck(:category, :name)
      existing_lookup = existing.each_with_object({}) do |(category, name), acc|
        acc[[category, normalized_key(name)]] = true
      end

      values_by_category.each do |category, values|
        values.each do |value|
          key = [category, normalized_key(value)]
          next if existing_lookup[key]

          rows << {
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

      Habitation.find_each do |habitation|
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

      Habitation.find_each do |habitation|
        normalize_items(habitation.infra_estrutura, category: "infrastructure").each { |item| values << item }
      end

      values.to_a.sort
    end

    def extract_unique_feature_values
      values = Set.new

      Habitation.find_each do |habitation|
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

      Address.where(addressable_type: "Habitation").find_each do |address|
        normalize_items(address.imediacoes, category: "feature").each { |item| values << item }
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
  end
end
