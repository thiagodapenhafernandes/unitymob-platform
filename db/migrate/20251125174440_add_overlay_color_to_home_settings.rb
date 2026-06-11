class AddOverlayColorToHomeSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :home_settings, :overlay_color, :string
  end
end
