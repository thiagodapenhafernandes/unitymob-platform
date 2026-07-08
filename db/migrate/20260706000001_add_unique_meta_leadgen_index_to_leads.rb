class AddUniqueMetaLeadgenIndexToLeads < ActiveRecord::Migration[7.1]
  # Fecha a corrida check-then-create do MetaLeadProcessingJob: unique parcial
  # em (tenant_id, other_information->>'meta_leadgen_id'), a MESMA expressão da
  # query de dedupe do job. O predicado precisa ser "expr IS NOT NULL" — é a
  # única implicação cross-clause que o planner deriva da igualdade estrita
  # (WHERE other_information ? 'meta_leadgen_id' seria ignorado pelo planner).
  INDEX_NAME = "index_leads_on_tenant_meta_leadgen".freeze

  def up
    # Neutraliza duplicatas existentes antes do unique: mantém o lead mais
    # antigo por (tenant_id, meta_leadgen_id) e move a chave dos mais novos
    # para "meta_leadgen_id_duplicado" (sai do índice parcial, mas fica
    # auditável no jsonb). UPDATE idempotente: re-execução não encontra rn > 1.
    affected = execute(<<~SQL).cmd_tuples
      WITH ranked AS (
        SELECT id,
               row_number() OVER (
                 PARTITION BY tenant_id, other_information->>'meta_leadgen_id'
                 ORDER BY created_at ASC, id ASC
               ) AS rn
        FROM leads
        WHERE other_information->>'meta_leadgen_id' IS NOT NULL
      )
      UPDATE leads
      SET other_information = (leads.other_information - 'meta_leadgen_id')
            || jsonb_build_object('meta_leadgen_id_duplicado', leads.other_information->'meta_leadgen_id')
      FROM ranked
      WHERE leads.id = ranked.id
        AND ranked.rn > 1
    SQL
    say "Leads duplicados de meta_leadgen_id neutralizados: #{affected}"

    execute <<~SQL
      CREATE UNIQUE INDEX IF NOT EXISTS #{INDEX_NAME}
      ON leads (tenant_id, (other_information->>'meta_leadgen_id'))
      WHERE (other_information->>'meta_leadgen_id') IS NOT NULL
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS #{INDEX_NAME}"
    # A neutralização de duplicatas não é revertida: a chave original fica
    # preservada em other_information->'meta_leadgen_id_duplicado'.
  end
end
