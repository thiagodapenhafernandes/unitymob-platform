class AddCommissionAmountsToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :valor_comissao_cents, :bigint
    add_column :habitations, :valor_livre_proprietario_cents, :bigint
  end
end
