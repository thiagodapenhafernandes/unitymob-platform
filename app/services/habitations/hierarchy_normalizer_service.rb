# frozen_string_literal: true

module Habitations
  class HierarchyNormalizerService
    def initialize(tenant: nil)
      @tenant = tenant || Current.tenant
      raise ArgumentError, "Tenant obrigatório para normalizar hierarquia de imóveis" if @tenant.blank?
    end

    def call
      now = Time.current

      mark_developments!(now)
      clear_parent_from_developments!(now)
      sync_units_from_parent!(now)
    end

    private

    def mark_developments!(now)
      habitation_scope.where(categoria: "Empreendimento")
                      .where.not(tipo: "Empreendimento")
                      .update_all(tipo: "Empreendimento", updated_at: now)

      habitation_scope.where.not(categoria: "Empreendimento")
                      .where(tipo: [nil, "", "Unitário"])
                      .update_all(tipo: "Unitário", updated_at: now)
    end

    def clear_parent_from_developments!(now)
      habitation_scope.where(tipo: "Empreendimento")
                      .where.not(codigo_empreendimento: [nil, ""])
                      .update_all(codigo_empreendimento: nil, updated_at: now)
    end

    def sync_units_from_parent!(now)
      quoted_now = Habitation.connection.quote(now.utc.strftime("%Y-%m-%d %H:%M:%S"))

      Habitation.connection.execute(<<~SQL.squish)
        UPDATE habitations AS habitation_unit
        SET nome_empreendimento = COALESCE(NULLIF(dev.nome_empreendimento, ''), dev.titulo_anuncio),
            constructor_id = COALESCE(dev.constructor_id, habitation_unit.constructor_id),
            updated_at = #{quoted_now}
        FROM habitations AS dev
        WHERE habitation_unit.codigo_empreendimento IS NOT NULL
          AND habitation_unit.codigo_empreendimento <> ''
          AND dev.codigo = habitation_unit.codigo_empreendimento
          AND dev.tenant_id = habitation_unit.tenant_id
          AND dev.tipo = 'Empreendimento'
          #{tenant_sql_condition("habitation_unit")}
      SQL
    end

    def habitation_scope
      @tenant.habitations
    end

    def tenant_sql_condition(table_alias)
      "AND #{table_alias}.tenant_id = #{Integer(@tenant.id)}"
    end
  end
end
