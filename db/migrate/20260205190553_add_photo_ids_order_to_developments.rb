class AddPhotoIdsOrderToDevelopments < ActiveRecord::Migration[7.1]
  def change
    add_column :developments, :photo_ids_order, :jsonb
  end
end
