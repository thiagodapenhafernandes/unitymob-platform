class CreateMetaCampaignInsights < ActiveRecord::Migration[7.1]
  def change
    create_table :meta_campaign_insights do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :ad_account_id, null: false, default: ""
      t.string :campaign_id, null: false, default: ""
      t.string :campaign_name, null: false, default: ""
      t.date :date, null: false
      t.decimal :spend, precision: 12, scale: 2, null: false, default: 0
      t.integer :impressions, null: false, default: 0
      t.integer :clicks, null: false, default: 0
      t.integer :leads, null: false, default: 0

      t.timestamps
    end

    add_index :meta_campaign_insights, [:tenant_id, :campaign_id, :date],
              unique: true, name: "index_meta_campaign_insights_unique_row"
    add_index :meta_campaign_insights, [:tenant_id, :date]
  end
end
