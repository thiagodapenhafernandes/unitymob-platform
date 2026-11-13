class AddDeliveryDestinationToDistributionRules < ActiveRecord::Migration[7.1]
  def change
    add_column :distribution_rules, :delivery_destination, :string, default: "unitymob", null: false
    add_check_constraint :distribution_rules, "delivery_destination IN ('unitymob', 'c2s')", name: "distribution_rule_delivery_destination"
  end
end
