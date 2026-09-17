class AddLoversSourceToDistributionRules < ActiveRecord::Migration[7.1]
  def change
    add_column :distribution_rules, :source_lovers, :boolean, default: false
  end
end
