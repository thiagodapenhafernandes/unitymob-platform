class CreateAiPropertySuggestions < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_property_suggestions do |t|
      t.references :habitation, null: false, foreign_key: true
      t.references :admin_user, null: true, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :generated_title
      t.text :generated_description
      t.text :generated_seo_keywords
      t.text :raw_response
      t.text :error_message
      t.datetime :applied_at

      t.timestamps
    end

    add_index :ai_property_suggestions, [:habitation_id, :status]
  end
end
