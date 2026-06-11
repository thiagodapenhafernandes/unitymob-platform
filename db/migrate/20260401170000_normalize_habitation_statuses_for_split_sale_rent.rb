class NormalizeHabitationStatusesForSplitSaleRent < ActiveRecord::Migration[7.1]
  def up
    # Renomeia status legados para a nomenclatura atual.
    execute <<~SQL
      UPDATE habitations
      SET status = 'Alugado imobiliária'
      WHERE status IN ('Alugado terceiros', 'Alugado Terceiros');
    SQL

    execute <<~SQL
      UPDATE habitations
      SET status = 'Vendido imobiliária'
      WHERE status IN ('Vendido terceiros', 'Vendido Terceiros');
    SQL

    # Remove status combinados, já que venda e locação são cadastros separados.
    execute <<~SQL
      UPDATE habitations
      SET status = CASE
        WHEN COALESCE(valor_venda_cents, 0) > 0 AND COALESCE(valor_locacao_cents, 0) = 0 THEN 'Venda'
        WHEN COALESCE(valor_locacao_cents, 0) > 0 AND COALESCE(valor_venda_cents, 0) = 0 THEN 'Locação'
        WHEN COALESCE(valor_venda_cents, 0) > 0 AND COALESCE(valor_locacao_cents, 0) > 0 THEN 'Venda'
        ELSE 'Venda'
      END
      WHERE status IN ('Venda e Locação', 'Venda e Aluguel');
    SQL
  end

  def down
    execute <<~SQL
      UPDATE habitations
      SET status = 'Alugado terceiros'
      WHERE status = 'Alugado imobiliária';
    SQL

    execute <<~SQL
      UPDATE habitations
      SET status = 'Vendido Terceiros'
      WHERE status = 'Vendido imobiliária';
    SQL
  end
end
