class CreateAddresses < ActiveRecord::Migration[7.1]
  def change
    create_table :addresses do |t|
      t.references :addressable, polymorphic: true, null: false
      t.string :tipo_endereco
      t.string :logradouro
      t.string :numero
      t.string :complemento
      t.string :bairro
      t.string :bairro_comercial
      t.string :cidade
      t.string :uf
      t.string :cep
      t.string :pais, default: "Brasil"
      t.decimal :latitude, precision: 10, scale: 7
      t.decimal :longitude, precision: 10, scale: 7
      t.text :imediacoes

      t.timestamps
    end
  end
end
