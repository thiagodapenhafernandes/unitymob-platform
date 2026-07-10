class AddExchangeComponentValuesToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :permuta_veiculo_valor_cents, :integer
    add_column :habitations, :permuta_outros_valor_cents, :integer
    add_column :habitations, :permuta_outros_descricao, :text
  end
end
