class AddSiteHiddenPhotoIdsToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :site_hidden_photo_ids, :jsonb, default: [], null: false
  end
end
