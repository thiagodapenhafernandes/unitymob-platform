module Ai
  module PropertySearch
    class FilterContract
      PROPERTY_TYPE_ALIASES = {
        "apartamento" => %w[apartment apartments apt apto flat flats],
        "casa" => %w[house houses home homes],
        "casa em condominio" => %w[casa em condominio casa condominio condo house condo house],
        "terreno" => %w[land lands lot lots plot plots],
        "comercial" => %w[commercial commercials office offices]
      }.freeze

      DEFINITIONS = {
        "transaction_type" => { setting: "transaction_type", type: "string", enum: %w[sale rent] },
        "property_type" => { setting: "property_type", type: "string" },
        "city" => { setting: "city", type: "string" },
        "neighborhood" => { setting: "neighborhood", type: "string" },
        "development_name" => { setting: "development", type: "string" },
        "developer_name" => { setting: "developer_name", type: "string" },
        "property_condition" => { setting: "property_condition", type: "string", enum: %w[launch ready under_construction] },
        "bedrooms_min" => { setting: "bedrooms", type: "integer" },
        "suites_min" => { setting: "suites", type: "integer" },
        "bathrooms_min" => { setting: "bathrooms", type: "integer" },
        "parking_spaces_min" => { setting: "parking_spaces", type: "integer" },
        "private_area_min" => { setting: "private_area", type: "number" },
        "private_area_max" => { setting: "private_area", type: "number" },
        "total_area_min" => { setting: "total_area", type: "number" },
        "total_area_max" => { setting: "total_area", type: "number" },
        "price_min" => { setting: "price", type: "number" },
        "price_max" => { setting: "price", type: "number" },
        "condominium_fee_max" => { setting: "condominium_fee", type: "number" },
        "property_tax_max" => { setting: "property_tax", type: "number" },
        "amenities" => { setting: "amenities", type: "array" },
        "property_code" => { setting: "property_code", type: "string" }
      }.freeze

      def initialize(setting)
        @setting = setting
      end

      def allowed_definitions
        DEFINITIONS.select do |key, definition|
          definition[:setting].in?(@setting.ai_property_search_allowed_fields) && definition_enabled?(key)
        end
      end

      def json_schema
        properties = allowed_definitions.transform_values { |definition| nullable_schema(definition) }
        {
          type: "object",
          additionalProperties: false,
          required: properties.keys,
          properties: properties
        }
      end

      def normalize(raw_filters)
        raw = raw_filters.respond_to?(:to_h) ? raw_filters.to_h.stringify_keys : {}
        allowed_definitions.each_with_object({}) do |(key, definition), result|
          value = normalize_value(raw[key], definition)
          result[key] = value unless value.nil? || (value.respond_to?(:empty?) && value.empty?)
        end
      end

      private

      def definition_enabled?(key)
        return @setting.ai_property_search_development_name_enabled? if key == "development_name"
        return @setting.ai_property_search_developer_name_enabled? if key == "developer_name"
        return @setting.ai_property_search_search_by_characteristics_enabled? if key == "property_condition"

        true
      end

      def nullable_schema(definition)
        value_schema = { type: definition[:type] }
        value_schema[:enum] = definition[:enum] if definition[:enum]
        value_schema[:items] = { type: "string" } if definition[:type] == "array"
        { anyOf: [value_schema, { type: "null" }] }
      end

      def normalize_value(value, definition)
        return if value.nil?

        case definition[:type]
        when "integer"
          integer = Integer(value, exception: false)
          integer if integer&.between?(0, 100)
        when "number"
          number = Float(value, exception: false)
          number&.round(2) if number&.between?(0, 1_000_000_000)
        when "array"
          Array(value).map { |item| sanitize_text(item, 80) }.compact_blank.first(20)
        else
          text = sanitize_text(value, 120)
          text = normalize_property_type(text) if definition[:setting] == "property_type"
          return text if definition[:enum].blank? || text.in?(definition[:enum])
        end
      end

      def sanitize_text(value, limit)
        value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").strip.first(limit).presence
      end

      def normalize_property_type(value)
        normalized_value = normalize_token(value)
        return value if normalized_value.blank?

        available_types.each do |option|
          return option if normalize_token(option) == normalized_value
        end

        PROPERTY_TYPE_ALIASES.each do |canonical, aliases|
          next unless aliases.include?(normalized_value)

          match = available_types.find { |option| normalize_token(option) == canonical }
          return match if match.present?
          return canonical.titleize
        end

        singularized = normalized_value.sub(/s\z/, "")
        available_types.find { |option| normalize_token(option).include?(singularized) } || value
      end

      def available_types
        @available_types ||= begin
          tenant = @setting.tenant
          types = tenant&.habitations&.public_property_types || []
          Array(types).map(&:to_s).compact_blank.uniq
        end
      end

      def normalize_token(value)
        DevelopmentAlias.normalize(value)
      end
    end
  end
end
