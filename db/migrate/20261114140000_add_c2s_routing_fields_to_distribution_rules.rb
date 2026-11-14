class AddC2sRoutingFieldsToDistributionRules < ActiveRecord::Migration[7.1]
  def change
    add_column :distribution_rules, :c2s_negotiation_type, :string
    add_column :distribution_rules, :c2s_negotiation_other, :string
    add_column :distribution_rules, :c2s_source, :string
    add_check_constraint :distribution_rules, "c2s_negotiation_type IS NULL OR c2s_negotiation_type IN ('Aluguel', 'Compra', 'Outros')", name: "distribution_rules_c2s_negotiation_type"
  end
end
