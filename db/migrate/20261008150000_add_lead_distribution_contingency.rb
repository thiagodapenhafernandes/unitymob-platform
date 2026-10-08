class AddLeadDistributionContingency < ActiveRecord::Migration[7.1]
  def change
    add_reference :distribution_rules, :contingency_rule, foreign_key: { to_table: :distribution_rules }
    add_column :distribution_rules, :contingency_enabled, :boolean, default: false, null: false
    add_column :distribution_rules, :contingency_triggers, :jsonb, default: [], null: false
    add_column :distribution_rules, :contingency_unavailable_minutes, :integer, default: 0, null: false
    add_column :distribution_rules, :contingency_pool_minutes, :integer, default: 30, null: false
    add_column :distribution_rules, :contingency_acceptance_minutes, :integer, default: 30, null: false
    add_reference :lead_settings, :default_distribution_rule, foreign_key: { to_table: :distribution_rules }
    add_column :leads, :distribution_cycle_started_at, :datetime
    add_reference :leads, :contingency_source_rule, foreign_key: { to_table: :distribution_rules }
    add_reference :leads, :contingency_target_rule, foreign_key: { to_table: :distribution_rules }
    add_column :leads, :contingency_forwarded_at, :datetime
    add_column :leads, :contingency_reason, :string
    add_column :leads, :contingency_pending, :boolean, default: false, null: false
    add_index :leads, [:tenant_id, :contingency_pending], where: "contingency_pending = true", name: "index_leads_on_pending_contingency"
    add_check_constraint :distribution_rules, "contingency_unavailable_minutes >= 0 AND contingency_pool_minutes > 0 AND contingency_acceptance_minutes > 0", name: "distribution_contingency_positive_times"
  end
end
