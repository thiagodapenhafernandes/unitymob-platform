# frozen_string_literal: true

class AddPartialIndexForWhatsappServiceContacts < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    add_index :leads, %i[tenant_id id],
      name: "idx_leads_whatsapp_service_contacts",
      where: "(other_information ->> 'whatsapp_service_contact') = 'true'",
      algorithm: :concurrently
  end

  def down
    remove_index :leads, name: "idx_leads_whatsapp_service_contacts", algorithm: :concurrently
  end
end
