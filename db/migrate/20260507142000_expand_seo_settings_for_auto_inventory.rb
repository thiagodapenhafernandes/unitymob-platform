class ExpandSeoSettingsForAutoInventory < ActiveRecord::Migration[7.1]
  def change
    change_column_null :seo_settings, :meta_title, true

    add_column :seo_settings, :canonical_key, :string
    add_column :seo_settings, :page_type, :string
    add_column :seo_settings, :controller_name, :string
    add_column :seo_settings, :action_name, :string
    add_column :seo_settings, :canonical_path, :string
    add_column :seo_settings, :normalized_params, :jsonb, default: {}, null: false
    add_column :seo_settings, :og_title, :string
    add_column :seo_settings, :og_description, :text
    add_column :seo_settings, :robots_index, :boolean, default: true, null: false
    add_column :seo_settings, :robots_follow, :boolean, default: true, null: false
    add_column :seo_settings, :active, :boolean, default: true, null: false
    add_column :seo_settings, :apply_to_public, :boolean, default: true, null: false
    add_column :seo_settings, :manual_mode, :boolean, default: false, null: false
    add_column :seo_settings, :auto_discovered, :boolean, default: false, null: false
    add_column :seo_settings, :ai_status, :string, default: "pending", null: false
    add_column :seo_settings, :ai_generated_at, :datetime
    add_column :seo_settings, :ai_error_message, :text
    add_column :seo_settings, :ai_insights, :text
    add_column :seo_settings, :seo_score, :integer, default: 0, null: false
    add_column :seo_settings, :access_count, :integer, default: 0, null: false
    add_column :seo_settings, :last_accessed_at, :datetime
    add_column :seo_settings, :last_generated_from_path, :string

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE seo_settings
          SET canonical_key = COALESCE(NULLIF(page_name, ''), 'legacy:' || id),
              page_type = COALESCE(page_type, 'legacy'),
              canonical_path = COALESCE(canonical_url, '/' || COALESCE(NULLIF(page_name, ''), '')),
              og_title = COALESCE(og_title, meta_title),
              og_description = COALESCE(og_description, meta_description)
          WHERE canonical_key IS NULL
        SQL
      end
    end

    change_column_null :seo_settings, :canonical_key, false
    add_index :seo_settings, :canonical_key, unique: true
    add_index :seo_settings, :page_type
    add_index :seo_settings, :last_accessed_at
    add_index :seo_settings, :seo_score
  end
end
