class AddCommercialTabFieldsToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :matricula_imovel, :string
    add_column :habitations, :zona, :string
    add_column :habitations, :aceita_doacao_flag, :boolean, default: false, null: false
    add_column :habitations, :condicoes_negociacao, :text
    add_column :habitations, :valor_locacao_anterior_cents, :integer
    add_column :habitations, :saldo_devedor_cents, :integer
    add_column :habitations, :numero_prestacoes, :integer
    add_column :habitations, :responsavel_reserva, :string
    add_column :habitations, :zelador_nome, :string
    add_column :habitations, :zelador_telefone, :string
    add_column :habitations, :observacoes_visitas, :text
    add_column :habitations, :regiao_foco, :string
  end
end
