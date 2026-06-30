# frozen_string_literal: true

require "csv"
require "fileutils"

module Habitations
  class InvalidParentReconciliationService
    Result = Struct.new(
      :invalid_total,
      :reconciled,
      :promoted_parents,
      :unresolved,
      :report_path,
      :rows,
      keyword_init: true
    )

    def initialize(apply: false, tenant: nil)
      @apply = apply
      @tenant = tenant || Current.tenant
      raise ArgumentError, "Tenant obrigatório para reconciliar pais de imóveis" if @tenant.blank?
      @now = Time.current
      @developments_by_code = load_developments_by_code
      @any_habitation_by_code = load_any_habitation_by_code
      @developments_by_name = load_developments_by_name
    end

    def call
      rows = []
      reconciled = 0
      promoted_parents = 0

      invalid_units.find_each do |unit|
        suggestion = find_suggestion(unit)
        applied = false
        promoted = false

        if @apply && suggestion
          promoted = promote_parent_if_needed!(suggestion[:parent]) if suggestion[:promote_parent]
          apply_reconciliation!(unit, suggestion[:parent])
          applied = true
          reconciled += 1
          promoted_parents += 1 if promoted
        end

        rows << build_row(unit, suggestion, applied, promoted)
      end

      report_path = write_report(rows)

      Result.new(
        invalid_total: rows.size,
        reconciled: reconciled,
        promoted_parents: promoted_parents,
        unresolved: rows.count { |row| row[:suggested_parent_code].blank? },
        report_path: report_path,
        rows: rows
      )
    end

    private

    attr_reader :tenant

    def invalid_units
      tenant.habitations.where.not(codigo_empreendimento: [nil, ""])
            .where.not(codigo_empreendimento: tenant.habitations.empreendimentos.select(:codigo))
    end

    def load_developments_by_code
      tenant.habitations.empreendimentos.where.not(codigo: [nil, ""]).index_by { |row| row.codigo.to_s }
    end

    def load_any_habitation_by_code
      tenant.habitations.where.not(codigo: [nil, ""]).index_by { |row| row.codigo.to_s }
    end

    def load_developments_by_name
      tenant.habitations.empreendimentos
            .where.not(nome_empreendimento: [nil, ""])
            .group_by { |row| normalized(row.nome_empreendimento) }
    end

    def find_suggestion(unit)
      current_parent_code = unit.codigo_empreendimento.to_s

      # Regra 1: pai existe por codigo, mas nao esta tipado como empreendimento.
      candidate_by_code = @any_habitation_by_code[current_parent_code]
      if candidate_by_code.present?
        if candidate_by_code.empreendimento?
          return { parent: candidate_by_code, strategy: "parent_code_exact", confidence: 1.0, promote_parent: false }
        end

        if candidate_by_code.categoria.to_s == "Empreendimento"
          return { parent: candidate_by_code, strategy: "parent_code_promote_category", confidence: 0.99, promote_parent: true }
        end
      end

      # Regra 2: match unico por nome_empreendimento da unidade.
      normalized_name = normalized(unit.nome_empreendimento)
      if normalized_name.present?
        list = @developments_by_name[normalized_name] || []
        if list.one?
          return { parent: list.first, strategy: "development_name_exact", confidence: 0.95, promote_parent: false }
        end
      end

      nil
    end

    def promote_parent_if_needed!(parent)
      return false if parent.blank? || parent.empreendimento?

      parent.update_columns(
        tipo: "Empreendimento",
        nome_empreendimento: parent.nome_empreendimento.presence || parent.titulo_anuncio,
        updated_at: @now
      )

      @developments_by_code[parent.codigo.to_s] = parent
      key = normalized(parent.nome_empreendimento)
      @developments_by_name[key] ||= []
      @developments_by_name[key] << parent unless @developments_by_name[key].any? { |row| row.id == parent.id }
      true
    end

    def apply_reconciliation!(unit, parent)
      unit.update_columns(
        codigo_empreendimento: parent.codigo,
        nome_empreendimento: parent.nome_empreendimento.presence || parent.titulo_anuncio,
        constructor_id: parent.constructor_id.presence || unit.constructor_id,
        construtora: parent.construtora.presence || unit.construtora,
        updated_at: @now
      )
    end

    def build_row(unit, suggestion, applied, promoted)
      parent = suggestion&.dig(:parent)

      {
        unit_id: unit.id,
        unit_code: unit.codigo,
        current_parent_code: unit.codigo_empreendimento,
        unit_name: unit.nome_empreendimento,
        suggested_parent_id: parent&.id,
        suggested_parent_code: parent&.codigo,
        suggested_parent_name: parent&.nome_empreendimento,
        strategy: suggestion&.dig(:strategy),
        confidence: suggestion&.dig(:confidence),
        applied: applied,
        parent_promoted_to_development: promoted
      }
    end

    def write_report(rows)
      FileUtils.mkdir_p(Rails.root.join("tmp", "reports"))
      path = Rails.root.join(
        "tmp",
        "reports",
        "invalid_parent_reconciliation_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv"
      )

      CSV.open(path, "w") do |csv|
        csv << rows.first&.keys || %w[unit_id unit_code current_parent_code]
        rows.each { |row| csv << row.values }
      end

      path.to_s
    end

    def normalized(value)
      I18n.transliterate(value.to_s).downcase.gsub(/\s+/, " ").strip
    end
  end
end
