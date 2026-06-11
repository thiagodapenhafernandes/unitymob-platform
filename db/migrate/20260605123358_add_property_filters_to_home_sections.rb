class AddPropertyFiltersToHomeSections < ActiveRecord::Migration[7.1]
  def change
    add_column :home_sections, :property_filters, :jsonb, null: false, default: {}
  end
end
