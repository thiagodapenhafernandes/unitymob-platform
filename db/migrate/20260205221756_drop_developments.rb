class DropDevelopments < ActiveRecord::Migration[7.1]
  def up
    remove_reference :habitations, :development, foreign_key: true, if_exists: true
    drop_table :developments, if_exists: true
  end

  def down
    create_table :developments do |t|
      t.string :name
      t.text :description
      t.jsonb :amenities, default: {}
      t.string :status
      t.string :slug
      t.string :address
      t.string :neighborhood
      t.string :city
      t.string :zip_code
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.references :constructor, foreign_key: true
    end
    add_reference :habitations, :development, foreign_key: true
  end
end
