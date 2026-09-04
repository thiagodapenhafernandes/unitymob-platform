class AddOpenAiResponseParametersToPropertySettings < ActiveRecord::Migration[7.1]
  def change
    change_table :property_settings, bulk: true do |t|
      t.decimal :ai_property_search_temperature, precision: 3, scale: 2, null: false, default: 0.20
      t.decimal :ai_property_search_top_p, precision: 3, scale: 2, null: false, default: 0.80
      t.decimal :ai_property_search_frequency_penalty, precision: 3, scale: 2, null: false, default: 0.50
      t.decimal :ai_property_search_presence_penalty, precision: 3, scale: 2, null: false, default: 0.20
    end
  end
end
