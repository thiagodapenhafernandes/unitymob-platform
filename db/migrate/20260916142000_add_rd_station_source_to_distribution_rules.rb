class AddRdStationSourceToDistributionRules < ActiveRecord::Migration[7.1]
  def change
    add_column :distribution_rules, :source_rd_station, :boolean, default: false
  end
end
