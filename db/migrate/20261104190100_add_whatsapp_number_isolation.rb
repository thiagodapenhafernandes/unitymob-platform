class AddWhatsappNumberIsolation < ActiveRecord::Migration[7.1]
  def up
    add_column :whatsapp_business_integrations, :separate_conversations_by_number, :boolean, null: false, default: false
    add_column :whatsapp_sender_numbers, :administrative_inbox_enabled, :boolean, null: false, default: true
    remove_index :whatsapp_conversations, name: "index_wa_conversations_on_tenant_and_phone"
    remove_index :whatsapp_conversations, name: "index_wa_conversations_on_tenant_and_bsuid"
    execute "CREATE UNIQUE INDEX index_wa_conversations_on_number_phone ON whatsapp_conversations (tenant_id, COALESCE(whatsapp_sender_number_id, 0), contact_phone) WHERE contact_phone IS NOT NULL"
    execute "CREATE UNIQUE INDEX index_wa_conversations_on_number_bsuid ON whatsapp_conversations (tenant_id, COALESCE(whatsapp_sender_number_id, 0), business_scoped_user_id) WHERE business_scoped_user_id IS NOT NULL"
  end

  def down
    if select_value("SELECT EXISTS (SELECT 1 FROM whatsapp_conversations GROUP BY tenant_id, contact_phone HAVING contact_phone IS NOT NULL AND COUNT(*) > 1)") ||
        select_value("SELECT EXISTS (SELECT 1 FROM whatsapp_conversations GROUP BY tenant_id, business_scoped_user_id HAVING business_scoped_user_id IS NOT NULL AND COUNT(*) > 1)")
      raise ActiveRecord::IrreversibleMigration, "Há conversas separadas por número. Concilie os históricos antes do rollback."
    end
    remove_index :whatsapp_conversations, name: "index_wa_conversations_on_number_phone"
    remove_index :whatsapp_conversations, name: "index_wa_conversations_on_number_bsuid"
    add_index :whatsapp_conversations, [:tenant_id, :contact_phone], unique: true, where: "contact_phone IS NOT NULL", name: "index_wa_conversations_on_tenant_and_phone"
    add_index :whatsapp_conversations, [:tenant_id, :business_scoped_user_id], unique: true, where: "business_scoped_user_id IS NOT NULL", name: "index_wa_conversations_on_tenant_and_bsuid"
    remove_column :whatsapp_sender_numbers, :administrative_inbox_enabled
    remove_column :whatsapp_business_integrations, :separate_conversations_by_number
  end
end
