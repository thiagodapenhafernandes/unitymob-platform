class AddCatalogContextLimitsToPropertySettings < ActiveRecord::Migration[7.1]
  def change
    change_table :property_settings, bulk: true do |t|
      t.integer :ai_property_search_catalog_property_types_limit, null: false, default: 12
      t.integer :ai_property_search_catalog_cities_limit, null: false, default: 12
      t.integer :ai_property_search_catalog_neighborhoods_limit, null: false, default: 18
      t.integer :ai_property_search_catalog_developments_limit, null: false, default: 12
      t.integer :ai_property_search_catalog_feature_terms_limit, null: false, default: 20
      t.integer :ai_property_search_catalog_alias_names_limit, null: false, default: 5
    end
  end
end
