class CreateHomeSectionItems < ActiveRecord::Migration[7.1]
  def change
    create_table :home_section_items do |t|
      t.references :home_section, null: false, foreign_key: true
      t.string :title
      t.text :description
      t.boolean :active
      t.integer :display_order

      t.timestamps
    end
  end
end
