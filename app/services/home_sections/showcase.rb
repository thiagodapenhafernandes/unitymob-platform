module HomeSections
  # Quais imóveis/empreendimentos uma seção mostra na Home. Fonte única: a home pública e a prévia do admin usam isto,
  # então "o que eu vejo ao configurar" é exatamente "o que o visitante vê".
  class Showcase
    PROPERTY_LIMIT = 12
    RENTAL_LIMIT = 6
    DEVELOPMENT_LIMIT = 12

    # O que pode ser escolhido/mostrado: imóveis publicados no site (status Venda, Aluguel ou Venda e Aluguel, com foto e preço)
    # ou, nas seções de empreendimentos, empreendimentos públicos com unidades. Usado pela Home, pela prévia e pelo seletor do admin.
    def self.eligible(habitations, development: false)
      return habitations.empreendimentos_publicos.where.not(codigo: nil) if development

      habitations.active.without_developments
    end

    def initialize(section, habitations:)
      @section = section
      @habitations = habitations
    end

    def rental?
      section.property_filter_enabled?("locacao") || section.section_type == "rentals"
    end

    def limit
      rental? ? RENTAL_LIMIT : PROPERTY_LIMIT
    end

    # Curadoria manual manda: havendo imóveis escolhidos, só eles aparecem e os filtros são ignorados.
    # Sem escolhidos, os filtros montam a vitrine (mais novos primeiro).
    def property_split
      manual = selected_ids(self.class.eligible(habitations), limit:)
      return { manual:, automatic: [] } if manual.any?

      automatic_scope = section.apply_property_filters(self.class.eligible(habitations))
      automatic_scope = automatic_scope.newest_first if automatic_scope.respond_to?(:newest_first)
      { manual: [], automatic: automatic_scope.limit(limit).pluck(:id) }
    end

    def property_ids
      property_split.values.flatten
    end

    # [[id, codigo], ...] sem códigos repetidos. Mesma regra: escolhidos manualmente substituem os filtros.
    def development_rows
      scope = self.class.eligible(habitations, development: true)
      manual_ids = selected_ids(scope, limit: DEVELOPMENT_LIMIT)
      if manual_ids.any?
        by_id = scope.where(id: manual_ids).pluck(:id, :codigo).to_h { |id, codigo| [id, [id, codigo]] }
        rows = manual_ids.filter_map { |id| by_id[id] }
      else
        rows = section.apply_property_filters(scope).newest_first.limit(20).pluck(:id, :codigo)
      end

      seen = Set.new
      rows.filter_map do |id, codigo|
        next if codigo.blank? || seen.include?(codigo)

        seen.add(codigo)
        [id, codigo]
      end.first(DEVELOPMENT_LIMIT)
    end

    private

    attr_reader :section, :habitations

    def selected_ids(scope, limit:)
      requested = section.selected_property_ids
      return [] if requested.empty?

      available = scope.where(id: requested).reorder(nil).pluck(:id).map(&:to_i)
      (requested & available).first(limit)
    end
  end
end
