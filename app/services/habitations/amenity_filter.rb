module Habitations
  class AmenityFilter
    def self.call(scope, amenity)
      new(scope, amenity).call
    end

    def initialize(scope, amenity)
      @scope = scope
      @key = I18n.transliterate(amenity.to_s).downcase
    end

    def call
      case @key
      when /frente mar/ then front_sea
      when /vista frente para o mar/ then @scope.where(vista_frente_mar_flag: true)
      when /vista para o mar/ then @scope.where("vista_frente_mar_flag = true OR unaccent(lower(descricao_web)) ILIKE unaccent(?)", "%vista%mar%")
      when /piscina/ then swimming_pool
      when /elevador/ then @scope.where("COALESCE(elevadores_qtd, 0) > 0")
      when /hidromassagem/ then @scope.where("COALESCE(hidromassagem_qtd, 0) > 0 OR searchable_features LIKE '%hidromassagem%'")
      when /jardim/ then @scope.where("garden_flag = true OR searchable_features LIKE '%jardim%'")
      when /garden/ then @scope.garden
      when /quadra.*mar/ then @scope.quadra_mar
      when /vista.*mar/ then @scope.vista_mar
      when /lavabo/ then @scope.lavabo
      when /depend.*empreg|wc.*empreg/ then @scope.dependencia_empregada
      when /sacada/ then @scope.where("varanda_gourmet_flag = true OR searchable_features LIKE '%sacada%'")
      when /mobiliado/ then @scope.where("mobiliado_flag = true OR searchable_features LIKE '%mobiliado%'")
      when /cozinha.*gourmet.*churrasqueir/ then @scope.cozinha_gourmet_churrasqueira
      when /sol.*manha/ then @scope.sol_manha
      when /sol.*tarde/ then @scope.sol_tarde
      when /sol.*dia.*todo/ then @scope.sol_dia_todo
      else textual_match
      end
    end

    private

    def front_sea
      @scope.where(
        "habitations.frente_mar_avenida_atlantica_flag IS TRUE OR " \
        "(jsonb_typeof(habitations.caracteristicas) = 'array' AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(habitations.caracteristicas) value WHERE unaccent(value) ILIKE unaccent('%frente mar%'))) OR " \
        "(jsonb_typeof(habitations.caracteristicas) = 'object' AND EXISTS (SELECT 1 FROM jsonb_each_text(habitations.caracteristicas) kv WHERE unaccent(kv.key) ILIKE unaccent('%frente mar%') OR unaccent(kv.value) ILIKE unaccent('%frente mar%'))) OR " \
        "EXISTS (SELECT 1 FROM unnest((#{Habitation::SearchScopes::UNIQUE_FEATURES_ARRAY_SQL})) AS feature WHERE unaccent(feature) ILIKE unaccent('%frente mar%'))"
      )
    end

    def swimming_pool
      @scope.where(
        "piscina_flag = true OR COALESCE(hidromassagem_qtd, 0) > 0 OR " \
        "(jsonb_typeof(infra_estrutura) = 'array' AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(infra_estrutura) value WHERE unaccent(lower(value)) ILIKE unaccent('%piscina%')))"
      )
    end

    def textual_match
      pattern = "%" + @key.gsub(/[^a-z0-9]+/, "%") + "%"
      @scope.where("searchable_features LIKE :pattern", pattern: pattern)
    end
  end
end
