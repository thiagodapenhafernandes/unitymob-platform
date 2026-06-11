class AddPremiumSeoTools < ActiveRecord::Migration[7.1]
  def change
    create_table :seo_redirects do |t|
      t.string :from_path, null: false
      t.string :to_path, null: false
      t.integer :status_code, null: false, default: 301
      t.boolean :active, null: false, default: true
      t.integer :hit_count, null: false, default: 0
      t.datetime :last_hit_at
      t.references :created_by_admin_user, foreign_key: { to_table: :admin_users }

      t.timestamps
    end

    add_index :seo_redirects, :from_path, unique: true
    add_index :seo_redirects, [:active, :from_path]

    create_table :seo_focus_keywords do |t|
      t.references :seo_setting, null: false, foreign_key: true
      t.string :keyword, null: false
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :seo_focus_keywords, [:seo_setting_id, :keyword], unique: true
    add_index :seo_focus_keywords, [:seo_setting_id, :position]

    create_table :seo_change_logs do |t|
      t.references :seo_setting, null: false, foreign_key: true
      t.references :admin_user, foreign_key: true
      t.string :event_type, null: false, default: "update"
      t.jsonb :changed_fields, null: false, default: {}
      t.jsonb :snapshot, null: false, default: {}

      t.timestamps
    end

    add_index :seo_change_logs, [:seo_setting_id, :created_at]
    add_index :seo_change_logs, :event_type
  end
end
