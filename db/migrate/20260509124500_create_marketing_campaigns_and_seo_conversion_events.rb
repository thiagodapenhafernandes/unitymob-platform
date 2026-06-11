class CreateMarketingCampaignsAndSeoConversionEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :marketing_campaigns do |t|
      t.references :seo_setting, foreign_key: true
      t.references :admin_user, foreign_key: true
      t.string :name, null: false
      t.string :channel, null: false, default: "organic"
      t.string :status, null: false, default: "idea"
      t.string :target_url
      t.string :objective
      t.integer :budget_cents, null: false, default: 0
      t.date :starts_on
      t.date :ends_on
      t.integer :priority, null: false, default: 3
      t.text :notes

      t.timestamps
    end

    add_index :marketing_campaigns, :status
    add_index :marketing_campaigns, :channel
    add_index :marketing_campaigns, :priority

    create_table :seo_conversion_events do |t|
      t.references :seo_setting, foreign_key: true
      t.references :marketing_campaign, foreign_key: true
      t.references :lead, foreign_key: true
      t.references :habitation, foreign_key: true
      t.string :event_type, null: false
      t.string :visitor_hash
      t.string :path
      t.string :source_path
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :seo_conversion_events, :event_type
    add_index :seo_conversion_events, :visitor_hash
    add_index :seo_conversion_events, :occurred_at
    add_index :seo_conversion_events, [:seo_setting_id, :event_type, :occurred_at], name: "index_seo_conversions_on_page_type_time"
  end
end
