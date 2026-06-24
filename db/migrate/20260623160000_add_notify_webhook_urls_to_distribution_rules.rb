class AddNotifyWebhookUrlsToDistributionRules < ActiveRecord::Migration[7.1]
  def change
    add_column :distribution_rules, :notify_webhook_urls, :jsonb, default: [], null: false
  end
end
