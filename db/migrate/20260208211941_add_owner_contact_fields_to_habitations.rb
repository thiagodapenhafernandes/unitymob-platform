class AddOwnerContactFieldsToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :proprietario_celular, :string
    add_column :habitations, :proprietario_telefone_comercial, :string
    add_column :habitations, :proprietario_telefone_residencial, :string
    add_column :habitations, :proprietario_email, :string
  end
end
