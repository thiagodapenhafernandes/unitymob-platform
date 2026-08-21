class AddQualificationToLeads < ActiveRecord::Migration[7.1]
  def change
    add_column :leads, :broker_qualification_status, :string
    add_column :leads, :manager_qualification_status, :string
    add_column :leads, :qualification_note, :text

    add_index :leads,
              [:tenant_id, :broker_qualification_status],
              name: "index_leads_on_tenant_and_broker_qualification"
    add_index :leads,
              [:tenant_id, :manager_qualification_status],
              name: "index_leads_on_tenant_and_manager_qualification"
  end
end
