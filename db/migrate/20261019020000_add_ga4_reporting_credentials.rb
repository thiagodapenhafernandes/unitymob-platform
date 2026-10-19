class AddGa4ReportingCredentials < ActiveRecord::Migration[7.1]
  def change
    add_column :ga4_conversion_configs, :reporting_enabled, :boolean, null: false, default: false
    add_column :ga4_conversion_configs, :reporting_property_id, :string
    add_column :ga4_conversion_configs, :reporting_credentials, :text
  end
end
