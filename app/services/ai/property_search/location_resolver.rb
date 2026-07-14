module Ai
  module PropertySearch
    # Corrige cidade/bairro interpretados contra os valores reais do tenant,
    # no mesmo espírito do DevelopmentResolver: casamento direto primeiro,
    # fuzzy pg_trgm como último recurso. O fuzzy roda sobre a lista canônica
    # cacheada (via unnest), nunca sobre a tabela de habitations.
    class LocationResolver
      Result = Data.define(:filters, :corrections)

      CACHE_TTL = 15.minutes

      def initialize(tenant:, setting:, filters:)
        @tenant = tenant
        @setting = setting
        @filters = filters.to_h.stringify_keys
      end

      def call
        return Result.new(filters: @filters, corrections: []) if @tenant.blank?

        filters = @filters.dup
        corrections = []

        if filters["city"].present?
          resolved_city = resolve(filters["city"], city_names)
          if resolved_city.present?
            corrections << correction("city", filters["city"], resolved_city)
            filters["city"] = resolved_city
          end
        end

        if filters["neighborhood"].present?
          resolved_neighborhood = resolve(filters["neighborhood"], neighborhood_names(filters["city"]))
          if resolved_neighborhood.present?
            corrections << correction("neighborhood", filters["neighborhood"], resolved_neighborhood)
            filters["neighborhood"] = resolved_neighborhood
          end
        end

        Result.new(filters: filters, corrections: corrections.compact)
      end

      private

      def resolve(term, candidates)
        return nil if candidates.empty?

        normalized_term = normalize(term)
        return nil if normalized_term.blank?

        exact = candidates.find { |candidate| normalize(candidate) == normalized_term }
        return exact if exact

        partial = candidates.find do |candidate|
          normalized_candidate = normalize(candidate)
          normalized_candidate.include?(normalized_term) || normalized_term.include?(normalized_candidate)
        end
        return partial if partial

        fuzzy_match(normalized_term, candidates)
      end

      def fuzzy_match(normalized_term, candidates)
        return nil unless @setting.ai_property_search_fuzzy_matching_enabled?

        row = ActiveRecord::Base.connection.select_one(
          ActiveRecord::Base.sanitize_sql_array([
            <<~SQL.squish, normalized_term, candidates, normalized_term, threshold
              SELECT name, similarity(LOWER(unaccent(name)), ?) AS score
              FROM unnest(ARRAY[?]::text[]) AS name
              WHERE similarity(LOWER(unaccent(name)), ?) >= ?
              ORDER BY score DESC
              LIMIT 1
            SQL
          ])
        )
        row&.fetch("name", nil)
      rescue StandardError => e
        Rails.logger.warn("[ai property search location] #{e.class}: #{e.message}")
        nil
      end

      def threshold
        value = if @setting.respond_to?(:ai_property_search_location_fuzzy_threshold)
          @setting.ai_property_search_location_fuzzy_threshold.to_f
        end
        value.to_f.positive? ? value.to_f : 0.40
      end

      def correction(field, from, to)
        return nil if normalize(from) == normalize(to)

        { field: field, from: from, to: to }
      end

      def normalize(value)
        Habitation.normalize_location_value(value)
      end

      def city_names
        Habitation.canonical_location_labels(location_rows.map(&:first))
      end

      def neighborhood_names(city)
        rows = location_rows
        if city.present?
          normalized_city = normalize(city)
          scoped = rows.select { |row_city, _| normalize(row_city) == normalized_city }
          rows = scoped if scoped.any?
        end
        Habitation.canonical_location_labels(rows.map(&:last))
      end

      def location_rows
        @location_rows ||= Rails.cache.fetch("ai_property_search/locations/#{@tenant.id}", expires_in: CACHE_TTL) do
          @tenant.habitations.publicly_listable
            .left_outer_joins(:address)
            .distinct
            .pluck(Arel.sql("#{Habitation::SearchScopes::LOCATION_CITY_SQL}, #{Habitation::SearchScopes::LOCATION_NEIGHBORHOOD_SQL}"))
            .map { |city, neighborhood| [city.to_s.strip, neighborhood.to_s.strip] }
        end
      end
    end
  end
end
