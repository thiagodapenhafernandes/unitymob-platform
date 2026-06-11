class AddPhotoIdsOrderToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :photo_ids_order, :jsonb, default: []
  end
end
