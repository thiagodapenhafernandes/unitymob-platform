class AddNumberAndNeighborhoodToStores < ActiveRecord::Migration[7.1]
  def change
    add_column :stores, :number, :string
    add_column :stores, :neighborhood, :string
  end
end
