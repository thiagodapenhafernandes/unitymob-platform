class ChangePositionToArrayInBanners < ActiveRecord::Migration[7.1]
  def up
    # Remove old enum column and add new array column
    remove_column :banners, :position
    add_column :banners, :positions, :string, array: true, default: []
  end
  
  def down
    remove_column :banners, :positions
    add_column :banners, :position, :integer, default: 0
  end
end
