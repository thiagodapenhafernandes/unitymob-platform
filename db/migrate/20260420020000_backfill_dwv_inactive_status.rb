class BackfillDwvInactiveStatus < ActiveRecord::Migration[7.1]
  # Imóveis DWV desativados localmente (exibir_no_site_flag=false) ficaram com
  # status original ("Venda" / "Aluguel" / "Diária") porque o
  # deactivate_removed_properties_by_ids antigo só mexia em exibir_no_site_flag.
  #
  # Aqui marcamos todos como "Suspenso" para coerência com filtros e relatórios.
  # Imóveis desativados que já tinham status terminal (Vendido/Alugado/Suspenso)
  # ficam intocados.
  def up
    execute <<~SQL.squish
      UPDATE habitations
      SET status = 'Suspenso'
      WHERE imovel_dwv = 'Sim'
        AND exibir_no_site_flag = false
        AND status IN ('Venda', 'Aluguel', 'Diária', 'Pendente', 'Lançamento')
    SQL

    rows = execute(<<~SQL.squish)
      SELECT status, COUNT(*) AS n
      FROM habitations
      WHERE imovel_dwv = 'Sim'
      GROUP BY status
      ORDER BY n DESC
    SQL
    say "Distribuição de status para imóveis DWV após backfill:"
    rows.each { |r| say "  #{r['status']}: #{r['n']}", true }
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
