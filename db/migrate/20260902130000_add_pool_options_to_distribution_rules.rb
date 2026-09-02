class AddPoolOptionsToDistributionRules < ActiveRecord::Migration[7.1]
  def change
    add_column :distribution_rules, :pocket_to_shark_tank, :boolean, null: false, default: false
    add_column :distribution_rules, :pool_renotify_mode, :string, null: false, default: "never"
    add_column :distribution_rules, :pool_renotify_minutes, :integer, null: false, default: 30
  end
end
