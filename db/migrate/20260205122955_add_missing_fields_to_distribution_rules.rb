class AddMissingFieldsToDistributionRules < ActiveRecord::Migration[7.1]
  def change
    add_column :distribution_rules, :source_site, :boolean, default: false
    add_column :distribution_rules, :auto_add_forms, :boolean, default: false
    add_column :distribution_rules, :notify_whatsapp, :boolean, default: false
    add_column :distribution_rules, :notify_email, :boolean, default: false
    add_column :distribution_rules, :notify_webhook, :boolean, default: false
    add_column :distribution_rules, :meta_page_ids, :jsonb, default: []
    add_column :distribution_rules, :neighborhoods, :jsonb, default: []
  end
end
