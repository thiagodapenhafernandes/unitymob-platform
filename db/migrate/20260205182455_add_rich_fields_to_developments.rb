class AddRichFieldsToDevelopments < ActiveRecord::Migration[7.1]
  def change
    add_column :developments, :address, :string
    add_column :developments, :neighborhood, :string
    add_column :developments, :city, :string
    add_column :developments, :zip_code, :string
    add_column :developments, :latitude, :decimal, precision: 10, scale: 7
    add_column :developments, :longitude, :decimal, precision: 10, scale: 7
    add_column :developments, :video_url, :string
    add_column :developments, :amenities, :jsonb, default: {}
    add_column :developments, :status, :string
    add_column :developments, :delivery_date, :date
    add_column :developments, :slug, :string
    add_index :developments, :slug
  end
end
