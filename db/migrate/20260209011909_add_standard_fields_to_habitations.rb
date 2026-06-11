class AddStandardFieldsToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :face, :string
    add_column :habitations, :perfil_construcao, :string
    add_column :habitations, :tipo_vaga, :string
    add_column :habitations, :hidromassagem_qtd, :integer
  end
end
