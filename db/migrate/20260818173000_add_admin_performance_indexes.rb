class AddAdminPerformanceIndexes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :lead_activities,
              [:tenant_id, :kind, :lead_id, :created_at],
              name: "idx_lead_activities_tenant_kind_lead_created",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :leads,
              [:tenant_id, :status, :updated_at],
              name: "idx_leads_tenant_status_updated_at",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :leads,
              [:tenant_id, :status, :admin_user_id],
              name: "idx_leads_tenant_status_admin_user",
              algorithm: :concurrently,
              if_not_exists: true

    add_index :active_storage_attachments,
              [:record_type, :name, :blob_id, :record_id],
              name: "idx_active_storage_attachments_record_name_blob",
              algorithm: :concurrently,
              if_not_exists: true
  end
end
