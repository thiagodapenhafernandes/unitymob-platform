class AddPictureUrlsToHabitationPhotoShares < ActiveRecord::Migration[7.1]
  def change
    add_column :habitation_photo_shares, :picture_urls, :jsonb, null: false, default: []
  end
end
