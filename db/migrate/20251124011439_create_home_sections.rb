class CreateHomeSections < ActiveRecord::Migration[7.1]
  def change
    create_table :home_sections do |t|
      t.integer :section_type
      t.string :title
      t.text :subtitle
      t.boolean :active
      t.integer :display_order

      t.timestamps
    end
  end
end
