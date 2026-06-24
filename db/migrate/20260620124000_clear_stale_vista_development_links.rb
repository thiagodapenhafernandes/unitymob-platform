class ClearStaleVistaDevelopmentLinks < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL.squish
      UPDATE habitations
      SET codigo_empreendimento = NULL,
          nome_empreendimento = NULL,
          updated_at = CURRENT_TIMESTAMP
      WHERE COALESCE(tipo, '') <> 'Empreendimento'
        AND NULLIF(BTRIM(codigo_empreendimento), '') IS NOT NULL
        AND ((vista_payload ? 'CodigoEmpreendimento') OR (vista_payload ? 'CodigoEmp'))
        AND COALESCE(
          NULLIF(BTRIM(CASE WHEN vista_payload ? 'CodigoEmpreendimento' THEN vista_payload->>'CodigoEmpreendimento' END), ''),
          NULLIF(BTRIM(CASE WHEN vista_payload ? 'CodigoEmp' THEN vista_payload->>'CodigoEmp' END), '')
        ) IS NULL
    SQL

    execute <<~SQL.squish
      UPDATE habitations
      SET titulo_anuncio = NULL,
          updated_at = CURRENT_TIMESTAMP
      WHERE vista_payload ? 'TituloSite'
        AND NULLIF(BTRIM(vista_payload->>'TituloSite'), '') IS NULL
        AND NULLIF(BTRIM(titulo_anuncio), '') IS NOT NULL
    SQL
  end

  def down
    # Dados obsoletos do Vista nao podem ser restaurados com seguranca.
  end
end
