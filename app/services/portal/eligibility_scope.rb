module Portal
  class EligibilityScope
    def initialize(integration)
      @integration = integration
    end

    def eligible_scope
      return Habitation.none if tenant_habitations.nil?

      scope = tenant_habitations.left_outer_joins(:address)
      scope = apply_portal_publication_filter(scope)
      scope = scope.where(status: @integration.allowed_statuses) if @integration.allowed_statuses.present?
      scope = apply_business_type(scope)
      scope = scope.where(exibir_no_site_flag: true) if @integration.require_exibir_no_site?
      scope = scope.where.not(codigo: [nil, ""]).where("COALESCE(habitations.titulo_anuncio, habitations.descricao_web, '') <> ''")
      scope = scope.where("COALESCE(addresses.cidade, habitations.cidade, '') <> ''")
      scope = scope.with_photos
      scope.distinct
    end

    def preview
      if tenant_habitations.nil?
        return { eligible_count: 0, rejected_count: 0, top_reasons: {} }
      end

      base = tenant_habitations.left_outer_joins(:address)
      reasons = Hash.new(0)

      reasons["sem_codigo"] = base.where(codigo: [nil, ""]).count

      if @integration.require_exibir_no_site?
        reasons["nao_exibir_no_site"] = base.where.not(exibir_no_site_flag: true).count
      end

      if @integration.allowed_statuses.present?
        reasons["status_nao_permitido"] = base.where.not(status: @integration.allowed_statuses).count
      end

      publication_filtered = apply_portal_publication_filter(base)
      reasons["nao_marcado_para_portal"] = base.where.not(id: publication_filtered.select(:id)).count

      reasons["tipo_negocio_nao_permitido"] = base.where.not(id: apply_business_type(base).select(:id)).count
      reasons["sem_conteudo"] = base.where("COALESCE(habitations.titulo_anuncio, habitations.descricao_web, '') = ''").count
      reasons["sem_localizacao"] = base.where("COALESCE(addresses.cidade, habitations.cidade, '') = ''").count
      reasons["sem_fotos"] = base.where.not(id: base.with_photos.select(:id)).count

      eligible_count = eligible_scope.count
      top_reasons = reasons.reject { |_, value| value <= 0 }.sort_by { |_, value| -value }.first(5).to_h

      {
        eligible_count: eligible_count,
        rejected_count: top_reasons.values.sum,
        top_reasons: top_reasons
      }
    end

    private

    # Base de imóveis SEMPRE escopada ao tenant da integração — impede que o
    # feed de um portal sirva habitations de outros tenants.
    # - Pré-migration (sem coluna tenant_id): Habitation global, preservando o
    #   comportamento antigo até a migration rodar.
    # - Pós-migration com tenant presente: tenant.habitations (isolamento).
    # - Pós-migration com tenant ausente (registro órfão): nil -> resultado vazio.
    def tenant_habitations
      return Habitation.all unless @integration.has_attribute?(:tenant_id)

      tenant = @integration.tenant
      return nil if tenant.nil?

      tenant.habitations
    end

    def apply_business_type(scope)
      types = @integration.allowed_business_types

      if types.include?("venda") && types.include?("aluguel")
        scope.where("valor_venda_cents > 0 OR valor_locacao_cents > 0")
      elsif types.include?("venda")
        scope.where("valor_venda_cents > 0")
      elsif types.include?("aluguel")
        scope.where("valor_locacao_cents > 0")
      else
        scope.none
      end
    end

    def apply_portal_publication_filter(scope)
      column = Habitation.portal_publication_column_for(@integration.portal)
      return scope if column.blank?

      scope.where(column => true)
    end
  end
end
