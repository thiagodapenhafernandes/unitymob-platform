class CreatePropertyPages < ActiveRecord::Migration[7.1]
  def change
    create_table :property_pages do |t|
      t.string :title, null: false
      t.string :meta_title
      t.text :meta_description
      t.string :slug, null: false
      t.jsonb :filter_params, default: {}
      t.boolean :active, default: true

      t.timestamps
    end

    add_index :property_pages, :slug, unique: true
  end
end
