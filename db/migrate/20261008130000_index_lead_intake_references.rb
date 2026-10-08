class IndexLeadIntakeReferences < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_index :lead_activities, "tenant_id, (metadata ->> 'ingress_reference')",
      name: "index_lead_activities_on_intake_reference",
      where: "kind = 'inquiry_complemented' AND metadata ? 'ingress_reference'",
      algorithm: :concurrently
    %w[email client_email].each do |column|
      add_index :leads, "tenant_id, lower(btrim(coalesce(#{column}, '')))",
        name: "index_leads_on_tenant_and_#{column}_trimmed", algorithm: :concurrently
    end
  end

  def down
    %w[email client_email].each do |column|
      remove_index :leads, name: "index_leads_on_tenant_and_#{column}_trimmed", algorithm: :concurrently
    end
    remove_index :lead_activities, name: "index_lead_activities_on_intake_reference", algorithm: :concurrently
  end
end
