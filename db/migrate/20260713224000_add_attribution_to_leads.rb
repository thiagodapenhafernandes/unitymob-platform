class AddAttributionToLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :leads, :attribution_channel, :string
    add_column :leads, :attribution_source, :string
    add_column :leads, :attribution_data, :jsonb, null: false, default: {}

    add_index :leads, [:tenant_id, :attribution_channel], name: "index_leads_on_tenant_and_attribution_channel"
  end
end
