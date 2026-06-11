# frozen_string_literal: true

module Habitations
  class HierarchyAuditService
    def initialize(strict: false)
      @strict = strict
    end

    def call
      result = {
        generated_at: Time.current.iso8601,
        metrics: metrics,
        samples: samples
      }

      raise "Hierarchy audit failed: #{result[:metrics].inspect}" if @strict && hard_fail?(result[:metrics])

      result
    end

    private

    def metrics
      linked_units = Habitation.where.not(codigo_empreendimento: [nil, ""])
      developments = Habitation.empreendimentos

      {
        developments_total: developments.count,
        developments_without_constructor: developments.where(constructor_id: nil).count,
        developments_without_name: developments.where(nome_empreendimento: [nil, ""]).count,
        duplicate_development_codes: duplicate_development_codes_count,
        units_linked_total: linked_units.count,
        units_with_invalid_parent: linked_units.where.not(codigo_empreendimento: developments.select(:codigo)).count,
        units_constructor_diff_from_parent: units_constructor_diff_from_parent_count,
        units_name_diff_from_parent: units_name_diff_from_parent_count
      }
    end

    def samples
      developments = Habitation.empreendimentos
      linked_units = Habitation.where.not(codigo_empreendimento: [nil, ""])

      {
        development_without_constructor: developments.where(constructor_id: nil).limit(10).pluck(:id, :codigo, :nome_empreendimento),
        unit_with_invalid_parent: linked_units.where.not(codigo_empreendimento: developments.select(:codigo)).limit(10).pluck(:id, :codigo, :codigo_empreendimento, :nome_empreendimento),
        unit_constructor_diff_from_parent: units_constructor_diff_from_parent_relation.limit(10).pluck("habitations.id", "habitations.codigo", "habitations.codigo_empreendimento", "habitations.constructor_id", "dev.constructor_id")
      }
    end

    def duplicate_development_codes_count
      Habitation.empreendimentos
                .where.not(codigo: [nil, ""])
                .group(:codigo)
                .having("count(*) > 1")
                .count
                .size
    end

    def units_constructor_diff_from_parent_relation
      Habitation.where.not(codigo_empreendimento: [nil, ""])
                .joins("INNER JOIN habitations dev ON dev.codigo = habitations.codigo_empreendimento")
                .where("dev.tipo = 'Empreendimento'")
                .where.not("dev.constructor_id IS NULL")
                .where.not("habitations.constructor_id IS NULL")
                .where("habitations.constructor_id <> dev.constructor_id")
    end

    def units_constructor_diff_from_parent_count
      units_constructor_diff_from_parent_relation.count
    end

    def units_name_diff_from_parent_count
      Habitation.where.not(codigo_empreendimento: [nil, ""])
                .joins("INNER JOIN habitations dev ON dev.codigo = habitations.codigo_empreendimento")
                .where("dev.tipo = 'Empreendimento'")
                .where(
                  "COALESCE(NULLIF(TRIM(habitations.nome_empreendimento), ''), '') <> COALESCE(NULLIF(TRIM(dev.nome_empreendimento), ''), '')"
                )
                .count
    end

    def hard_fail?(metrics)
      metrics[:units_with_invalid_parent].positive? ||
        metrics[:duplicate_development_codes].positive? ||
        metrics[:units_constructor_diff_from_parent].positive?
    end
  end
end
