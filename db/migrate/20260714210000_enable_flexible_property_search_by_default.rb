class EnableFlexiblePropertySearchByDefault < ActiveRecord::Migration[7.1]
  def up
    change_column_default :property_settings, :ai_property_search_allow_flexible_results, from: false, to: true
    execute <<~SQL.squish
      UPDATE property_settings
      SET ai_property_search_allow_flexible_results = TRUE
      WHERE ai_property_search_allow_flexible_results = FALSE
    SQL
  end

  def down
    change_column_default :property_settings, :ai_property_search_allow_flexible_results, from: true, to: false
  end
end
