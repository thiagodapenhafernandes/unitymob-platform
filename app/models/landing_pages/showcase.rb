# Resultado do bloco "Vitrine de imóveis": os filtros FIXOS da página definem o universo e, quando o bloco
# tem filtros do visitante, o que o visitante escolhe REFINA dentro dele (AND) — nunca amplia a seleção.
module LandingPages
  class Showcase
    Result = Struct.new(:habitations, :total, keyword_init: true)

    # Parâmetros que o visitante pode usar para refinar (mesmos nomes da listagem principal do site).
    VISITOR_SCALAR_KEYS = %w[transaction_type neighborhood min_bedrooms min_suites min_parking min_area min_price max_price target_price sort].freeze
    VISITOR_ARRAY_KEYS = %w[category city development characteristics].freeze

    def self.permitted_visitor_params(params)
      params.permit(*VISITOR_SCALAR_KEYS, **VISITOR_ARRAY_KEYS.index_with { [] })
    end

    def initialize(scope:, block:, visitor_params: {}, page: 1)
      @scope = scope
      @block = block
      @visitor_params = visitor_params.to_h.with_indifferent_access.compact_blank
      @page = page
    end

    def call
      relation = @scope.active.advanced_search(fixed_params)
      relation = relation.advanced_search(visitor_search_params) if visitor_search_params.except(:sort).present?

      habitations = relation
        .includes(:address, { constructor: { logo_attachment: :blob } }, { empreendimento: { constructor: { logo_attachment: :blob } } })
        .paginate(page: @page, per_page: @block.value(:per_page) || 12)
      PublicSite::CardPhotoPreloader.new(habitations.to_a, limit: 3).call
      Result.new(habitations: habitations, total: habitations.total_entries)
    end

    private

    # Filtros da página (os mesmos que a landing usava) + ordem: o visitante pode trocar a ordem.
    def fixed_params
      @block.value(:filters).to_h.except("sort").merge("sort" => @visitor_params[:sort].presence || @block.value(:sort).presence)
    end

    def visitor_search_params
      @visitor_search_params ||= begin
        params = @visitor_params.except(:sort)
        # "Valor aproximado" busca ±20%, como na listagem principal.
        target = params.delete(:target_price).to_s.gsub(/\D/, "").to_i
        params.merge!(min_price: (target * 0.8).to_i, max_price: (target * 1.2).to_i) if target.positive?
        params
      end
    end
  end
end
