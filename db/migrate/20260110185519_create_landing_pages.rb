class CreateLandingPages < ActiveRecord::Migration[7.1]
  def change
    create_table :landing_pages do |t|
      t.string :title
      t.string :slug
      t.jsonb :filters
      t.string :meta_title
      t.text :meta_description
      t.text :content
      t.boolean :active
      t.text :description

      t.timestamps
    end
  end
end
