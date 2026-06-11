class CreateDevelopments < ActiveRecord::Migration[7.1]
  def change
    create_table :developments do |t|
      t.string :name
      t.text :description
      t.bigint :price_min
      t.bigint :price_max
      t.decimal :area_min
      t.decimal :area_max
      t.integer :bedrooms_min
      t.integer :bedrooms_max
      t.references :constructor, null: false, foreign_key: true

      t.timestamps
    end
  end
end
