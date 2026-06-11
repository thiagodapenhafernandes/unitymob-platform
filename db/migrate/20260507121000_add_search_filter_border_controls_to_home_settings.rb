class AddSearchFilterBorderControlsToHomeSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :home_settings, :search_filter_border_enabled, :boolean, default: true, null: false
    add_column :home_settings, :search_filter_border_opacity, :decimal, precision: 3, scale: 2
  end
end
