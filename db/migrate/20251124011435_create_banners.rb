class CreateBanners < ActiveRecord::Migration[7.1]
  def change
    create_table :banners do |t|
      t.string :title
      t.text :description
      t.string :link_url
      t.string :link_text
      t.integer :position
      t.boolean :active
      t.integer :display_order

      t.timestamps
    end
  end
end
