class AddAiPropertySearchToPropertySettings < ActiveRecord::Migration[7.1]
  def change
    change_table :property_settings, bulk: true do |t|
      t.boolean :ai_property_search_enabled, null: false, default: false
      t.boolean :voice_property_search_enabled, null: false, default: false
      t.text :ai_property_search_instructions
      t.string :ai_property_search_welcome_message
      t.string :ai_property_search_processing_message
      t.string :ai_property_search_no_results_message
      t.string :ai_property_search_data_source, null: false, default: "database"
      t.text :ai_property_search_allowed_fields, array: true, null: false, default: []
      t.text :ai_property_search_result_fields, array: true, null: false, default: []
      t.integer :ai_property_search_max_results, null: false, default: 20
      t.string :ai_property_search_default_sort, null: false, default: "relevance"
      t.boolean :ai_property_search_allow_flexible_results, null: false, default: false
      t.integer :ai_property_search_price_tolerance_percentage, null: false, default: 10
      t.boolean :ai_property_search_allow_clarifying_questions, null: false, default: true
      t.boolean :ai_property_search_require_filter_confirmation, null: false, default: false
      t.integer :ai_property_search_max_audio_duration_seconds, null: false, default: 60
      t.string :ai_property_search_language, null: false, default: "pt-BR"
      t.text :ai_property_search_allowed_profiles, array: true, null: false, default: []
      t.boolean :ai_property_search_history_enabled, null: false, default: false
      t.integer :ai_property_search_history_retention_days, null: false, default: 30
    end

    create_table :ai_property_search_histories do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :admin_user, null: false, foreign_key: true
      t.references :selected_habitation, null: true, foreign_key: { to_table: :habitations }
      t.string :original_audio_reference
      t.text :transcription
      t.jsonb :interpreted_filters, null: false, default: {}
      t.integer :result_count, null: false, default: 0
      t.integer :processing_time_ms
      t.string :status, null: false
      t.text :error_message
      t.timestamps
    end

    add_index :ai_property_search_histories, [:tenant_id, :created_at], name: "idx_ai_property_search_history_retention"
  end
end
