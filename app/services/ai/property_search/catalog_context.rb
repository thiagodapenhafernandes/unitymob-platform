require "json"

module Ai
  module PropertySearch
    class CatalogContext
      DEFAULT_LIMITS = {
        property_types: 12,
        cities: 12,
        neighborhoods: 18,
        developments: 12,
        feature_terms: 20,
        alias_names: 5
      }.freeze

      def initialize(setting:, tenant:, text:, current_filters: {})
        @setting = setting
        @tenant = tenant
        @text = text.to_s
        @current_filters = current_filters
      end

      def call
        {
          tenant: tenant_payload,
          search_config: search_config_payload,
          current_filters: current_filters_payload,
          catalog: catalog_payload
        }.compact
      end

      private

      attr_reader :setting, :tenant, :text, :current_filters

      def tenant_payload
        {
          id: tenant.id,
          language: setting.ai_property_search_language
        }
      end

      def search_config_payload
        {
          allowed_fields: Array(setting.ai_property_search_allowed_fields).map(&:to_s),
          result_fields: Array(setting.ai_property_search_result_fields).map(&:to_s),
          default_sort: setting.ai_property_search_default_sort,
          max_results: setting.ai_property_search_max_results,
          data_source: setting.ai_property_search_data_source,
          development_resolution: {
            enabled: setting.ai_property_search_development_name_enabled?,
            developer_enabled: setting.ai_property_search_developer_name_enabled?,
            aliases_enabled: setting.ai_property_search_development_aliases_enabled?,
            fuzzy_enabled: setting.ai_property_search_fuzzy_matching_enabled?,
            fuzzy_similarity_threshold: setting.ai_property_search_fuzzy_similarity_threshold.to_f,
            characteristics_enabled: setting.ai_property_search_search_by_characteristics_enabled?
          }
        }
      end

      def current_filters_payload
        filters = Ai::PropertySearch::FilterContract.new(setting).normalize(current_filters)
        filters.presence
      end

      def catalog_payload
        payload = {}
        payload[:property_types] = property_types if allowed_field?("property_type")
        payload[:transaction_types] = transaction_types if allowed_field?("transaction_type")
        payload[:cities] = location_summary(:city) if allowed_field?("city")
        payload[:neighborhoods] = location_summary(:neighborhood) if allowed_field?("neighborhood")
        payload[:developments] = development_candidates if development_context_allowed?
        payload[:feature_terms] = feature_terms if allowed_field?("amenities") || allowed_field?("property_condition")
        payload.compact_blank
      end

      def property_types
        scope = catalog_scope
        scope.group(:categoria).count
          .sort_by { |name, count| [-count.to_i, name.to_s] }
          .first(limit_for(:property_types))
          .map { |name, count| { name: name.to_s, count: count.to_i } }
          .reject { |item| item[:name].blank? }
      end

      def transaction_types
        values = []
        values << { name: "sale", count: catalog_scope.where("valor_venda_cents > 0").count }
        values << { name: "rent", count: catalog_scope.where("valor_locacao_cents > 0").count }
        values.reject { |item| item[:count].to_i.zero? }
      end

      def location_summary(kind)
        expr = kind == :city ? Habitation::SearchScopes::LOCATION_CITY_SQL : Habitation::SearchScopes::LOCATION_NEIGHBORHOOD_SQL
        catalog_scope
          .left_outer_joins(:address)
          .group(Arel.sql(expr))
          .count
          .sort_by { |name, count| [-count.to_i, name.to_s] }
          .first(limit_for(kind == :city ? :cities : :neighborhoods))
          .map { |name, count| { name: name.to_s, count: count.to_i } }
          .reject { |item| item[:name].blank? }
      end

      def development_candidates
        records = matching_developments
        records = fallback_developments if records.empty?

        records.first(limit_for(:developments)).map do |record|
          {
            name: development_name(record),
            aliases: development_aliases(record),
            developer_name: record.construtora.presence,
            city: record_city(record),
            neighborhood: record_neighborhood(record),
            property_type: record.categoria.presence,
            highlights: development_highlights(record)
          }.compact_blank
        end
      end

      def feature_terms
        terms = tenant.attribute_options
          .where(context: "habitation")
          .where(category: %w[feature infrastructure])
          .order(name: :asc)
          .limit(limit_for(:feature_terms))
          .pluck(:name)

        terms.map(&:to_s).compact_blank.uniq
      rescue StandardError
        []
      end

      def matching_developments
        scope = tenant.habitations.where(tipo: "Empreendimento")
        scope = scope.left_outer_joins(:address)
        scope = scope.left_outer_joins(:development_aliases) if setting.ai_property_search_development_aliases_enabled?

        terms = search_terms
        return scope.order(updated_at: :desc).limit(DEFAULT_LIMITS[:developments]).to_a if terms.empty?

        search_blob = development_search_blob_sql
        patterns = terms.map { "%#{ActiveRecord::Base.sanitize_sql_like(term)}%" }
        where_sql = terms.map { "#{search_blob} LIKE ?" }.join(" OR ")
        scope
          .where(where_sql, *patterns)
          .distinct
          .order(updated_at: :desc)
          .limit(limit_for(:developments) * 2)
          .to_a
      rescue StandardError
        []
      end

      def fallback_developments
        tenant.habitations
          .where(tipo: "Empreendimento")
          .order(updated_at: :desc)
          .limit(limit_for(:developments) * 2)
          .to_a
      end

      def development_search_blob_sql
        alias_name = setting.ai_property_search_development_aliases_enabled? ? "COALESCE(development_aliases.normalized_name, '')" : "''"
        "regexp_replace(unaccent(lower(CONCAT_WS(' ', habitations.nome_empreendimento, habitations.titulo_anuncio, habitations.construtora, COALESCE(addresses.cidade, habitations.cidade, ''), COALESCE(addresses.bairro, habitations.bairro, ''), #{alias_name}))), '[^a-z0-9]+', ' ', 'g')"
      end

      def search_terms
        tokens = DevelopmentAlias.normalize(text).split(/\s+/)
        tokens.concat(extract_terms_from_filters)
        tokens
          .map(&:to_s)
          .map(&:strip)
          .reject(&:blank?)
          .reject { |token| stopword?(token) || token.length < 3 || token.match?(/\A\d+\z/) }
          .uniq
          .first(8)
      end

      def extract_terms_from_filters
        filters = FilterContract.new(setting).normalize(current_filters)
        filters.values.flat_map do |value|
          case value
          when Array
            value.map { |item| DevelopmentAlias.normalize(item) }
          else
            DevelopmentAlias.normalize(value)
          end
        end
      end

      def stopword?(token)
        %w[
          a ai ao aos as com da das de do dos e em entre essa esse isso
          eu foi ir la lá na nas no nos o os para por pra que quer quero
          um uma umae uns umas venda aluguel locacao locação apartamento
          apartamentos casa casas imovel imóvel imóveis imoveis
          frente mar frente-mar meio mil milhao milhoes milhão milhões bi bilhao bilhões
          ate até partir nova novo busca pesquisa
        ].include?(token)
      end

      def development_name(record)
        record.nome_empreendimento.presence || record.titulo_anuncio.presence || record.codigo
      end

      def development_aliases(record)
        record.development_aliases
          .order(:name)
          .limit(limit_for(:alias_names))
          .pluck(:name)
      rescue StandardError
        []
      end

      def development_highlights(record)
        highlights = []
        highlights << "lançamento" if record.lancamento_flag?
        highlights.concat(Array(record.caracteristicas_predio)).concat(Array(record.caracteristicas_imovel))
        highlights.map(&:to_s).map(&:strip).reject(&:blank?).uniq.first(5)
      rescue StandardError
        []
      end

      def record_city(record)
        record.address&.cidade.presence || record.cidade.presence
      end

      def record_neighborhood(record)
        record.address&.bairro.presence || record.bairro.presence
      end

      def catalog_scope
        tenant.habitations.publicly_listable
      end

      def development_context_allowed?
        allowed_field?("development") || allowed_field?("developer_name") || allowed_field?("property_condition")
      end

      def allowed_field?(field)
        Array(setting.ai_property_search_allowed_fields).map(&:to_s).include?(field.to_s)
      end

      def limit_for(key)
        setting.catalog_limit_value(key)
      rescue NoMethodError
        DEFAULT_LIMITS.fetch(key)
      end
    end
  end
end
