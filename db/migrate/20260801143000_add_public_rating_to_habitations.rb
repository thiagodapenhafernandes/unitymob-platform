class AddPublicRatingToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :public_rating_value, :decimal, precision: 3, scale: 2
    add_column :habitations, :public_rating_count, :integer
    add_column :habitations, :public_rating_source, :string
  end
end
