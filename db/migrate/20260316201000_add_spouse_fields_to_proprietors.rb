class AddSpouseFieldsToProprietors < ActiveRecord::Migration[7.1]
  def change
    add_column :proprietors, :spouse_name, :string
    add_column :proprietors, :spouse_email, :string
    add_column :proprietors, :spouse_phone, :string
    add_column :proprietors, :spouse_cpf_cnpj, :string

    add_index :proprietors, :spouse_name
    add_index :proprietors, :spouse_email
    add_index :proprietors, :spouse_cpf_cnpj
  end
end
