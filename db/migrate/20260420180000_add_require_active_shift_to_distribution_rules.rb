class AddRequireActiveShiftToDistributionRules < ActiveRecord::Migration[7.1]
  def change
    add_column :distribution_rules, :require_active_shift, :boolean, default: false, null: false
  end
end
