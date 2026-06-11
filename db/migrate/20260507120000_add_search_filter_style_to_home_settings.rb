class AddSearchFilterStyleToHomeSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :home_settings, :search_filter_background_color, :string
    add_column :home_settings, :search_filter_background_opacity, :decimal, precision: 3, scale: 2
    add_column :home_settings, :search_filter_border_color, :string
    add_column :home_settings, :search_filter_text_color, :string
    add_column :home_settings, :search_filter_field_background_color, :string
    add_column :home_settings, :search_filter_field_background_opacity, :decimal, precision: 3, scale: 2
    add_column :home_settings, :search_filter_backdrop_blur, :integer
  end
end
