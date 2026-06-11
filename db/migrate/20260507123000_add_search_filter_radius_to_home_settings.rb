class AddSearchFilterRadiusToHomeSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :home_settings, :search_filter_border_radius, :integer
  end
end
