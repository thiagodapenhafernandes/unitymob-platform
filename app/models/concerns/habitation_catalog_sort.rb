module HabitationCatalogSort
  DEFAULT_CODIGO_SORT_SQL = "CASE WHEN (habitations.codigo ~ '^[0-9]+$') THEN habitations.codigo::bigint ELSE 0 END"
  LATEST_HUMAN_ACTIVITY_SQL = <<~SQL.squish.freeze
    COALESCE(
      (
        SELECT MAX(habitation_audit_logs.created_at)
        FROM habitation_audit_logs
        WHERE habitation_audit_logs.habitation_id = habitations.id
          AND habitation_audit_logs.tenant_id = habitations.tenant_id
          AND habitation_audit_logs.source IN ('admin', 'captacao')
      ),
      habitations.data_cadastro_crm,
      habitations.created_at
    )
  SQL
  SORT_OPTIONS = {
    "data_cadastro_crm" => { label: "Última atividade", column: LATEST_HUMAN_ACTIVITY_SQL, default_direction: "desc" },
    "codigo" => { label: "Código mais recente", column: DEFAULT_CODIGO_SORT_SQL, default_direction: "desc" },
    "categoria" => { label: "Categoria", column: "categoria", default_direction: "asc" },
    "endereco" => { label: "Endereço", column: "endereco", default_direction: "asc" },
    "numero" => { label: "Endereço número", column: "numero", default_direction: "asc" },
    "complemento" => { label: "Endereço complemento", column: "complemento", default_direction: "asc" },
    "dormitorios_qtd" => { label: "Dormitório", column: "dormitorios_qtd", default_direction: "desc" },
    "valor_venda_cents" => { label: "Valor venda", column: "valor_venda_cents", default_direction: "desc" },
    "valor_locacao_cents" => { label: "Valor aluguel", column: "valor_locacao_cents", default_direction: "desc" },
    "bairro_comercial" => { label: "Bairro comercial", column: "bairro_comercial", default_direction: "asc" },
    "nome_empreendimento" => { label: "Empreendimento", column: "nome_empreendimento", default_direction: "asc" },
    "valor_m2_aluguel" => { label: "Valor M2 aluguel", column: "valor_por_m2_cents", default_direction: "desc" },
    "valor_por_m2_cents" => { label: "Valor M2 venda", column: "valor_por_m2_cents", default_direction: "desc" },
    "valor_total_aluguel_cents" => { label: "Valor total aluguel", column: "valor_total_aluguel_cents", default_direction: "desc" }
  }.freeze
end
