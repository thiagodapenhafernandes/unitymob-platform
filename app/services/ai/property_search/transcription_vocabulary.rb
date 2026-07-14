module Ai
  module PropertySearch
    # Monta o prompt de vocabulário enviado à transcrição de áudio para que
    # nomes próprios do tenant (cidades, bairros, empreendimentos) sejam
    # reconhecidos com a grafia correta. O modelo dá mais peso ao final do
    # prompt, então bairros e empreendimentos (onde a transcrição mais erra)
    # ficam por último.
    class TranscriptionVocabulary
      MAX_CHARS = 900
      CITIES_LIMIT = 10
      NEIGHBORHOODS_LIMIT = 25
      DEVELOPMENTS_LIMIT = 15
      CACHE_TTL = 1.hour

      def initialize(tenant:, setting:)
        @tenant = tenant
        @setting = setting
      end

      def call
        return nil if @tenant.blank?

        Rails.cache.fetch("ai_property_search/vocab/#{@tenant.id}", expires_in: CACHE_TTL) do
          build_prompt
        end.presence
      end

      private

      def build_prompt
        terms = (cities + neighborhoods + developments).map { |name| name.to_s.strip }.compact_blank.uniq
        return "" if terms.empty?

        prompt = "Vocabulário: "
        terms.each do |term|
          candidate = prompt == "Vocabulário: " ? "#{prompt}#{term}" : "#{prompt}, #{term}"
          break if candidate.length > MAX_CHARS

          prompt = candidate
        end
        prompt << "."
      end

      def cities
        location_names(Habitation::SearchScopes::LOCATION_CITY_SQL, CITIES_LIMIT)
      end

      def neighborhoods
        location_names(Habitation::SearchScopes::LOCATION_NEIGHBORHOOD_SQL, NEIGHBORHOODS_LIMIT)
      end

      def location_names(expr, limit)
        @tenant.habitations.publicly_listable
          .left_outer_joins(:address)
          .group(Arel.sql(expr))
          .count
          .sort_by { |name, count| [-count.to_i, name.to_s] }
          .first(limit)
          .filter_map { |name, _count| name.presence }
      rescue StandardError
        []
      end

      def developments
        names = @tenant.habitations
          .where(tipo: "Empreendimento")
          .order(updated_at: :desc)
          .limit(DEVELOPMENTS_LIMIT)
          .pluck(:nome_empreendimento)
        names += DevelopmentAlias.where(tenant: @tenant).order(updated_at: :desc).limit(DEVELOPMENTS_LIMIT).pluck(:name)
        names
      rescue StandardError
        []
      end
    end
  end
end
