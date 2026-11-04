class AddDistributionRuleOrganization < ActiveRecord::Migration[7.1]
  def change
    add_column :distribution_rules, :archived_at, :datetime
    add_column :distribution_rules, :display_position, :integer, null: false, default: 0
    add_index :distribution_rules, [:tenant_id, :archived_at, :display_position], name: "index_distribution_rules_on_display_order"
    add_column :home_settings, :corporate_title, :string, null: false, default: "Private Corporate"
  end
end
