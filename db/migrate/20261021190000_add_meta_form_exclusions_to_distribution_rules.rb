class AddMetaFormExclusionsToDistributionRules < ActiveRecord::Migration[7.1]
  def change
    add_column :distribution_rules, :excluded_meta_form_ids, :jsonb, default: [], null: false
  end
end
