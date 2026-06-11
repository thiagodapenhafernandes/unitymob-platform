class ExpandMarketingCampaignMetrics < ActiveRecord::Migration[7.1]
  def change
    add_column :marketing_campaigns, :slug, :string
    add_column :marketing_campaigns, :utm_source, :string
    add_column :marketing_campaigns, :utm_medium, :string
    add_column :marketing_campaigns, :utm_campaign, :string
    add_column :marketing_campaigns, :utm_term, :string
    add_column :marketing_campaigns, :utm_content, :string
    add_column :marketing_campaigns, :clicks_count, :integer, null: false, default: 0
    add_column :marketing_campaigns, :conversions_count, :integer, null: false, default: 0
    add_column :marketing_campaigns, :last_clicked_at, :datetime

    add_index :marketing_campaigns, :slug, unique: true
    add_index :marketing_campaigns, :utm_campaign
    add_index :marketing_campaigns, :last_clicked_at
  end
end
