module PublicSite
  # Catálogo do menu de navegação (overlay): grupos de categorias com contagem
  # de imóveis públicos, na mesma regra da busca (public_property_search), para
  # cada link cair numa listagem que existe. Itens sem imóvel somem.
  #
  #   PublicSite::CatalogNavigation.call(tenant:)
  #   # => [{ title:, count:, filters:, action_label:, links: [{ label:, count:, filters: }] }]
  #
  # ponytail: ~35 COUNTs no cache miss (30 min por tenant, renovado quando um
  # imóvel muda); agrupar em uma consulta só se isso aparecer no APM.
  class CatalogNavigation
    HOUSES = ["Casa", "Casa em Condomínio", "Sobrado"].freeze

    def self.call(tenant:, limit: 5)
      new(tenant:, limit:).call
    end

    def initialize(tenant:, limit:)
      @tenant = tenant
      @limit = limit.to_i.positive? ? limit.to_i : 5
    end

    def call
      Rails.cache.fetch(cache_key, expires_in: 30.minutes) { build_groups.compact }
    end

    private

    attr_reader :tenant, :limit

    def build_groups
      [
        group("Todos os imóveis", filters: {}, items: [
          item("Apartamentos", category: ["Apartamento"]),
          item("Casas", category: HOUSES),
          item("Terrenos", category: ["Terreno", "Terreno em Condomínio"])
        ]),
        dynamic_group("Construtoras", top_constructors.map { |name, count| item_payload(name, count, constructor: name) }),
        group("Apartamentos", filters: { category: ["Apartamento"] }, action_label: "ver todos", items: [
          item("Apartamentos 1 Dormitório", category: ["Apartamento"], bedrooms: 1),
          item("Apartamentos 2 Dormitórios", category: ["Apartamento"], bedrooms: 2),
          item("Apartamentos 3 Dormitórios", category: ["Apartamento"], bedrooms: 3),
          item("Apartamentos 4 ou + Dorms.", category: ["Apartamento"], min_bedrooms: 4),
          item("Apartamentos Garden", category: ["Garden"]),
          item("Coberturas", category: ["Cobertura"]),
          item("Duplex / Triplex", category: ["Duplex", "Triplex"]),
          item("Mobiliados", category: ["Apartamento"], characteristics: ["mobiliado"])
        ]),
        group("Aps com suíte", filters: { category: ["Apartamento"], min_suites: 1 }, action_label: "ver todos", items: [
          item("Apartamentos 1 Suíte", category: ["Apartamento"], suites: 1),
          item("Apartamentos 2 Suítes", category: ["Apartamento"], suites: 2),
          item("Apartamentos 3 Suítes", category: ["Apartamento"], suites: 3),
          item("Apartamentos 4 ou + Suítes", category: ["Apartamento"], min_suites: 4)
        ]),
        group("Casas", filters: { category: HOUSES }, action_label: "ver todas", items: [
          item("Casas 3 Dormitórios", category: HOUSES, bedrooms: 3),
          item("Casas 4 ou + Dorms.", category: HOUSES, min_bedrooms: 4),
          item("Casas com suíte", category: HOUSES, min_suites: 1)
        ]),
        dynamic_group("Regiões e destaques", top_cities.map { |city, count| item_payload(city, count, city: [city]) } + [
          item("Lançamento", characteristics: ["lancamento"]),
          item("Em construção", characteristics: ["em_construcao"]),
          item("Pronto para morar", characteristics: ["pronto"]),
          item("Frente para o mar", characteristics: ["frente_mar"]),
          item("Quadra do mar", characteristics: ["quadra_mar"])
        ].compact)
      ]
    end

    def group(title, filters:, items:, action_label: nil)
      count = count_for(filters)
      links = items.compact
      return if count.zero? || links.empty?

      { title:, count:, filters:, action_label:, links: }
    end

    def dynamic_group(title, links)
      return if links.empty?

      { title:, links: }
    end

    def item(label, filters)
      count = count_for(filters)
      item_payload(label, count, filters) if count.positive?
    end

    def item_payload(label, count, filters)
      { label:, count:, filters: }
    end

    def count_for(filters)
      tenant.habitations.public_property_search(filters).unscope(:order).count
    end

    def top_constructors
      tenant.habitations.public_property_listable
        .where.not(construtora: [nil, ""])
        .group(:construtora)
        .count
        .sort_by { |name, count| [-count, name.to_s] }
        .first(limit)
    end

    # Rótulo canônico (mesma grafia do filtro de localização), então o link filtra.
    def top_cities
      tenant.habitations.public_city_link_groups(cities: limit, neighborhoods: 0).map { |group| [group[:value], group[:count]] }
    end

    def cache_key
      updated_at = tenant.habitations.maximum(:updated_at)&.utc&.to_i || 0
      "public_catalog_navigation_v2/tenant/#{tenant.id}/#{updated_at}/#{limit}"
    end
  end
end
