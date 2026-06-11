class AddInfrastructureFieldsToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :tipo_fachada, :string
    add_column :habitations, :andares_qtd, :integer
  end
end
