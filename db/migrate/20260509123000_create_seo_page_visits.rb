class CreateSeoPageVisits < ActiveRecord::Migration[7.1]
  def change
    create_table :seo_page_visits do |t|
      t.references :seo_setting, null: false, foreign_key: true
      t.string :visitor_hash, null: false
      t.string :session_hash
      t.string :user_agent_hash
      t.string :path, null: false
      t.date :visited_on, null: false
      t.integer :visits_count, null: false, default: 1
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false

      t.timestamps
    end

    add_index :seo_page_visits,
              [:seo_setting_id, :visitor_hash, :visited_on],
              unique: true,
              name: "index_seo_page_visits_on_page_visitor_day"
    add_index :seo_page_visits, [:visited_on, :seo_setting_id]
    add_index :seo_page_visits, :visitor_hash
  end
end
