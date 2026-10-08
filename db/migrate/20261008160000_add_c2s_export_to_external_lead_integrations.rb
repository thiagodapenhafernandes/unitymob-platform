# frozen_string_literal: true

class AddC2sExportToExternalLeadIntegrations < ActiveRecord::Migration[7.1]
  def change
    change_table :external_lead_integrations, bulk: true do |t|
      t.boolean :export_enabled, null: false, default: false
      t.string :export_endpoint, null: false, default: "/leads"
      t.integer :exported_count, null: false, default: 0
      t.integer :export_failed_count, null: false, default: 0
      t.datetime :last_exported_at
      t.text :last_export_error
    end

    add_column :leads, :c2s_export_external_id, :string
    add_column :leads, :c2s_exported_at, :datetime
    add_index :leads, [:tenant_id, :c2s_export_external_id], unique: true, where: "c2s_export_external_id IS NOT NULL", name: "index_leads_on_tenant_c2s_export_id"
  end
end
