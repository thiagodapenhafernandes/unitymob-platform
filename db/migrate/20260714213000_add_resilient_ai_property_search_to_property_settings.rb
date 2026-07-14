class AddResilientAiPropertySearchToPropertySettings < ActiveRecord::Migration[7.1]
  def change
    change_table :property_settings, bulk: true do |t|
      t.boolean :ai_property_search_transcription_vocabulary_enabled, null: false, default: true
      t.boolean :ai_property_search_resilient_search_enabled, null: false, default: false
      t.decimal :ai_property_search_location_fuzzy_threshold, precision: 3, scale: 2, null: false, default: 0.40
    end
  end
end
