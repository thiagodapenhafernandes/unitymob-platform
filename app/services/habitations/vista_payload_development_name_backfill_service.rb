# frozen_string_literal: true

module Habitations
  class VistaPayloadDevelopmentNameBackfillService
    Result = Struct.new(:candidates, :updated, :skipped, :samples, keyword_init: true)

    def initialize(tenant:, apply: false, limit: nil)
      @tenant = tenant
      @apply = apply
      @limit = limit&.to_i
      raise ArgumentError, "Tenant obrigatório" if @tenant.blank?
    end

    def call
      candidates = candidate_count
      updated = 0
      skipped = 0
      samples = []

      candidate_scope.find_each do |habitation|
        name = development_name_from_payload(habitation)

        if name.blank?
          skipped += 1
          next
        end

        samples << sample_for(habitation, name) if samples.size < 20

        if apply
          habitation.update_columns(nome_empreendimento: name) # rubocop:disable Rails/SkipsModelValidations
          updated += 1
        end
      end

      clear_filter_options_cache if updated.positive?

      Result.new(candidates: candidates, updated: updated, skipped: skipped, samples: samples)
    end

    private

    attr_reader :tenant, :apply, :limit

    def candidate_scope
      scope = tenant.habitations
                    .where(Habitation::VISTA_REFERENCE_CODIGO_SQL)
                    .where("COALESCE(tipo, '') <> 'Empreendimento'")
                    .where("NULLIF(BTRIM(nome_empreendimento), '') IS NULL OR nome_empreendimento = '.'")
                    .where("NULLIF(BTRIM(vista_payload->>'Empreendimento'), '') IS NOT NULL")
                    .order(Arel.sql("codigo::bigint ASC"))

      limit.present? && limit.positive? ? scope.limit(limit) : scope
    end

    def candidate_count
      candidate_scope.count
    end

    def development_name_from_payload(habitation)
      return if Habitation.standalone_category_without_development_name?(habitation.categoria)

      raw_name = habitation.vista_payload.to_h["Empreendimento"].to_s.strip
      return if raw_name.blank? || raw_name == "."

      raw_name
    end

    def sample_for(habitation, name)
      {
        codigo: habitation.codigo,
        categoria: habitation.categoria,
        before: habitation.nome_empreendimento,
        after: name
      }
    end

    def clear_filter_options_cache
      Rails.cache.delete("admin/habitations/form_options/v2/tenant/#{tenant.id}")
    end
  end
end
