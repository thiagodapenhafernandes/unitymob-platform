class CreateSeoSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :seo_settings do |t|
      t.string :page_name
      t.string :meta_title
      t.text :meta_description
      t.text :meta_keywords
      t.string :og_image
      t.string :canonical_url

      t.timestamps
    end
  end
end
