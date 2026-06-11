class AddWebhookUrlToDistributionRules < ActiveRecord::Migration[7.1]
  def change
    add_column :distribution_rules, :webhook_url, :string
  end
end
