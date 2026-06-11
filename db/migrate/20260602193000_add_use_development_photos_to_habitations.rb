class AddUseDevelopmentPhotosToHabitations < ActiveRecord::Migration[7.1]
  def change
    add_column :habitations, :use_development_photos_flag, :boolean, null: false, default: false
  end
end
