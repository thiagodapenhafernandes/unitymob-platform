class AddPropertyCitiesToDistributionRules < ActiveRecord::Migration[7.1]
  def change
    add_column :distribution_rules, :property_cities, :jsonb, null: false, default: []
  end
end
