# frozen_string_literal: true

module Habitations
  class HierarchyNormalizerService
    def call
      now = Time.current

      mark_developments!(now)
      clear_parent_from_developments!(now)
      sync_units_from_parent!(now)
    end

    private

    def mark_developments!(now)
      Habitation.where(categoria: "Empreendimento")
                .where.not(tipo: "Empreendimento")
                .update_all(tipo: "Empreendimento", updated_at: now)

      Habitation.where.not(categoria: "Empreendimento")
                .where(tipo: [nil, "", "Unitário"])
                .update_all(tipo: "Unitário", updated_at: now)
    end

    def clear_parent_from_developments!(now)
      Habitation.where(tipo: "Empreendimento")
                .where.not(codigo_empreendimento: [nil, ""])
                .update_all(codigo_empreendimento: nil, updated_at: now)
    end

    def sync_units_from_parent!(now)
      Habitation.connection.execute(<<~SQL.squish)
        UPDATE habitations AS unit
        SET nome_empreendimento = COALESCE(NULLIF(dev.nome_empreendimento, ''), dev.titulo_anuncio),
            constructor_id = COALESCE(dev.constructor_id, unit.constructor_id),
            updated_at = '#{now.utc.strftime("%Y-%m-%d %H:%M:%S")}'
        FROM habitations AS dev
        WHERE unit.codigo_empreendimento IS NOT NULL
          AND unit.codigo_empreendimento <> ''
          AND dev.codigo = unit.codigo_empreendimento
          AND dev.tipo = 'Empreendimento'
      SQL
    end
  end
end
