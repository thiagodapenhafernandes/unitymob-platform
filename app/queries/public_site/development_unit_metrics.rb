module PublicSite
  # Números dos cards de empreendimento em lote (uma consulta por página, não
  # por card): unidades de cada empreendimento e faixas de metragem, suítes,
  # quartos e vagas das unidades publicadas. Usado na home e em /empreendimentos.
  #
  #   metrics = PublicSite::DevelopmentUnitMetrics.new(tenant.habitations, codes)
  #   metrics.unit_counts  # => { "3650" => 114 }
  #   metrics.unit_metrics # => { "3650" => { area_label:, suites_label:, dorms_label:, vagas_label: } }
  class DevelopmentUnitMetrics
    def initialize(scope, development_codes)
      @scope = scope
      @codes = Array(development_codes).compact_blank.uniq
    end

    def unit_counts
      return {} if codes.empty?

      # Mesmo conjunto das faixas do card (unit_metrics): só unidades
      # visíveis no site e com preço. Sem isso o card exibe o total do
      # cadastro (ex.: 35) em vez das unidades consultáveis.
      @unit_counts ||= scope.publicly_listable
        .with_public_listing_price
        .where(codigo_empreendimento: codes)
        .group(:codigo_empreendimento).count
    end

    def unit_metrics
      return {} if codes.empty?

      @unit_metrics ||= begin
        grouped = Hash.new { |hash, key| hash[key] = { areas: [], suites: [], dorms: [], vagas: [] } }
        scope.publicly_listable
          .with_public_listing_price
          .where(codigo_empreendimento: codes)
          .pluck(:codigo_empreendimento, :area_privativa_m2, :suites_qtd, :dormitorios_qtd, :vagas_qtd)
          .each do |codigo, area, suites, dorms, vagas|
            grouped[codigo][:areas] << area if area.to_f.positive?
            grouped[codigo][:suites] << suites if suites.to_i.positive?
            grouped[codigo][:dorms] << dorms if dorms.to_i.positive?
            grouped[codigo][:vagas] << vagas if vagas.to_i.positive?
          end

        grouped.transform_values do |values|
          {
            area_label: area_range_label(values[:areas]),
            suites_label: integer_range_label(values[:suites]),
            dorms_label: integer_range_label(values[:dorms]),
            vagas_label: integer_range_label(values[:vagas])
          }
        end
      end
    end

    private

    attr_reader :scope, :codes

    def integer_range_label(values)
      normalized = values.map(&:to_i).select(&:positive?).uniq.sort
      return if normalized.empty?

      normalized.size == 1 ? normalized.first.to_s : "#{normalized.min} a #{normalized.max}"
    end

    def area_range_label(values)
      normalized = values.map(&:to_i).select(&:positive?)
      return if normalized.empty?

      normalized.min == normalized.max ? "#{normalized.min} m²" : "#{normalized.min} a #{normalized.max} m²"
    end
  end
end
