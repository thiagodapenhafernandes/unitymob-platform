class CreateProprietorsAndLinkToHabitations < ActiveRecord::Migration[7.1]
  def change
    create_table :proprietors do |t|
      t.string :name, null: false
      t.integer :role, null: false, default: 0
      t.string :vista_code
      t.string :cpf_cnpj
      t.string :rg_ie
      t.string :issuing_authority
      t.date :birth_date
      t.string :email
      t.string :phone_primary
      t.string :mobile_phone
      t.string :residential_phone
      t.string :business_phone
      t.string :phone_extension
      t.string :profession
      t.string :marital_status
      t.string :marriage_regime
      t.string :nationality
      t.string :capture_vehicle
      t.date :registered_at
      t.text :notes
      t.boolean :is_client, default: false, null: false
      t.string :address_type
      t.string :street
      t.string :number
      t.string :complement
      t.string :block
      t.string :uf, limit: 2
      t.string :cep, limit: 10
      t.string :neighborhood
      t.string :city

      t.timestamps
    end

    add_index :proprietors, :vista_code
    add_index :proprietors, :cpf_cnpj
    add_index :proprietors, :email
    add_index :proprietors, :name

    add_reference :habitations, :proprietor, foreign_key: true
  end
end
