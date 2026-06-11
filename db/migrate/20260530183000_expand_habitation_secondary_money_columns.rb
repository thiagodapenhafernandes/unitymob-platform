class ExpandHabitationSecondaryMoneyColumns < ActiveRecord::Migration[7.1]
  def change
    change_column :habitations, :valor_venda_anterior_cents, :bigint
    change_column :habitations, :valor_total_aluguel_cents, :bigint
    change_column :habitations, :valor_promocional_cents, :bigint
    change_column :habitations, :valor_aceito_permuta_cents, :bigint
    change_column :habitations, :permuta_valor_cents, :bigint
    change_column :habitations, :valor_locacao_anterior_cents, :bigint
    change_column :habitations, :saldo_devedor_cents, :bigint
  end
end
