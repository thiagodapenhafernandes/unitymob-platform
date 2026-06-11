class AddPermutaFieldsToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :valor_aceito_permuta_cents, :integer
    add_column :habitations, :aceita_permuta_veiculo_flag, :boolean, default: false, null: false
    add_column :habitations, :aceita_permuta_imovel_flag, :boolean, default: false, null: false
    add_column :habitations, :aceita_permuta_outros_flag, :boolean, default: false, null: false
    add_column :habitations, :tipo_veiculo_aceito_permuta, :string
    add_column :habitations, :ano_minimo_veiculo_aceito_permuta, :integer
    add_column :habitations, :permuta_valor_cents, :integer
    add_column :habitations, :permuta_localizacao, :string
    add_column :habitations, :permuta_dormitorios_qtd, :integer
    add_column :habitations, :permuta_suites_qtd, :integer
    add_column :habitations, :permuta_garagens_qtd, :integer
  end
end
