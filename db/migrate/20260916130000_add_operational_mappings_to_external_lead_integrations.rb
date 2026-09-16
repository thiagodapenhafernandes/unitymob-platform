class AddOperationalMappingsToExternalLeadIntegrations < ActiveRecord::Migration[7.1]
  def change
    return unless table_exists?(:external_lead_integrations)
    return if column_exists?(:external_lead_integrations, :operational_mappings)

    add_column :external_lead_integrations, :operational_mappings, :jsonb, null: false, default: {}
  end
end
