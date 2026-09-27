module PublicSite
  # Faixas e limites de preço da busca pública calculados pelo estoque da conta.
  # Fonte única para o slider do drawer, a busca do hero e os filtros da
  # listagem quando a conta não personalizou as faixas no Perfil público.
  #
  #   PublicSite::PriceRanges.for(tenant)
  #   # => { "venda" => { min:, max:, step:, ranges: [[label, "min-max"], ...], count: }, "aluguel" => {...} }
  #
  # Com menos de MIN_LISTINGS imóveis naquele tipo de negócio devolve nil para
  # ele — quem chama cai nos valores padrão.
  class PriceRanges
    MIN_LISTINGS = 8
    COLUMNS = { "venda" => "valor_venda_cents", "aluguel" => "valor_locacao_cents" }.freeze

    def self.for(tenant)
      return {} unless tenant

      Rails.cache.fetch(cache_key(tenant.id), expires_in: 6.hours) { new(tenant).call }
    end

    def self.cache_key(tenant_id)
      "public_price_ranges_v1/tenant/#{tenant_id}"
    end

    # "Até R$ 1,5 mi", "R$ 1,5 mi a R$ 3 mi", "Acima de R$ 5 mi" (valores em reais).
    def self.label_for(minimum, maximum)
      minimum = minimum.to_i
      maximum = maximum.to_i
      return "Até #{short_money(maximum)}" if minimum.zero? && maximum.positive?
      return "Acima de #{short_money(minimum)}" if maximum.zero? && minimum.positive?
      return "#{short_money(minimum)} a #{short_money(maximum)}" if minimum.positive? && maximum.positive?

      "Todos os valores"
    end

    def self.short_money(reais)
      value = reais.to_i
      if value >= 1_000_000
        "R$ #{format_short(value / 1_000_000.0)} mi"
      elsif value >= 1_000
        "R$ #{format_short(value / 1_000.0)} mil"
      else
        "R$ #{value}"
      end
    end

    def self.format_short(number)
      rounded = number.round(1)
      rounded == rounded.to_i ? rounded.to_i.to_s : rounded.to_s.tr(".", ",")
    end

    def initialize(tenant)
      @tenant = tenant
    end

    def call
      COLUMNS.to_h { |transaction, column| [transaction, stats_for(column)] }.compact_blank
    end

    private

    attr_reader :tenant

    def stats_for(column)
      scope = tenant.habitations.public_filterable_locations.where("habitations.#{column} > 0")
      row = scope.pick(
        Arel.sql("COUNT(*)"),
        *[0.02, 0.25, 0.5, 0.75, 0.98].map { |p| Arel.sql("PERCENTILE_CONT(#{p}) WITHIN GROUP (ORDER BY habitations.#{column})") }
      )
      count, p02, p25, p50, p75, p98 = row
      return if count.to_i < MIN_LISTINGS

      p02, p25, p50, p75, p98 = [p02, p25, p50, p75, p98].map { |cents| cents.to_f / 100 }
      step = step_for(p98)
      minimum = (p02 / step).floor * step
      maximum = (p98 / step).ceil * step
      maximum += step if maximum <= minimum

      breaks = [p25, p50, p75].map { |value| nice(value) }.uniq.select { |value| value > minimum && value < maximum }
      ranges = if breaks.empty?
        []
      else
        # Mesmo formato de valor que a busca lê em price_range: "min-max", máximo vazio = "acima de".
        [[0, breaks.first], *breaks.each_cons(2).to_a, [breaks.last, 0]].map do |low, high|
          [self.class.label_for(low, high), "#{low}-#{high.positive? ? high : ""}"]
        end
      end

      { min: minimum.to_i, max: maximum.to_i, step: step.to_i, ranges: ranges, count: count.to_i }
    end

    # Dois algarismos significativos: 1.234.567 -> 1.200.000; 4.560 -> 4.600.
    def nice(value)
      return 0 if value <= 0

      magnitude = 10**(Math.log10(value).floor - 1)
      ((value / magnitude).round * magnitude).to_i
    end

    # Passo do slider proporcional à escala dos preços da conta.
    def step_for(top)
      return 1_000 if top <= 0

      [10**(Math.log10(top).floor - 2), 100].max
    end
  end
end
