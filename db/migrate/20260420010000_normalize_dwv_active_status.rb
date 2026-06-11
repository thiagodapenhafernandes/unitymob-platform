class NormalizeDwvActiveStatus < ActiveRecord::Migration[7.1]
  # Imóveis DWV importados antes do fix de map_status ficaram com status="Active"
  # (titleize de "active" sem mapeamento). Aqui inferimos pelo preço:
  # - tem valor_venda_cents > 0 → "Venda"
  # - senão tem valor_locacao_cents > 0 → "Aluguel"
  # - nem um nem outro → mantém sem alteração (provável imóvel inativo já)
  def up
    execute <<~SQL.squish
      UPDATE habitations
      SET status = 'Venda'
      WHERE status = 'Active' AND valor_venda_cents > 0
    SQL

    execute <<~SQL.squish
      UPDATE habitations
      SET status = 'Aluguel'
      WHERE status = 'Active' AND (valor_venda_cents IS NULL OR valor_venda_cents = 0) AND valor_locacao_cents > 0
    SQL

    rows = execute("SELECT COUNT(*) AS n FROM habitations WHERE status = 'Active'")
    say "Imóveis ainda com status='Active' (sem preço informado): #{rows.first['n']}", true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
