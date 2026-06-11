class CreateFooterStores < ActiveRecord::Migration[7.1]
  def change
    create_table :footer_stores do |t|
      t.string :name
      t.string :address
      t.string :zip_code
      t.string :creci
      t.string :phone
      t.integer :position

      t.timestamps
    end
  end
end
