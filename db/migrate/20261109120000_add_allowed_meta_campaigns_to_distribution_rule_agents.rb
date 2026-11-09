class AddAllowedMetaCampaignsToDistributionRuleAgents < ActiveRecord::Migration[7.1]
  def change
    add_column :distribution_rule_agents, :allowed_meta_campaign_ids, :jsonb, default: [], null: false
    add_check_constraint :distribution_rule_agents, "jsonb_typeof(allowed_meta_campaign_ids) = 'array'", name: "distribution_agents_campaigns_array"
  end
end
