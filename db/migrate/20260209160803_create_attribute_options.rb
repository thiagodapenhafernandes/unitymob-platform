class CreateAttributeOptions < ActiveRecord::Migration[7.1]
  def change
    create_table :attribute_options do |t|
      t.string :name
      t.string :category
      t.string :context

      t.timestamps
    end
  end
end
