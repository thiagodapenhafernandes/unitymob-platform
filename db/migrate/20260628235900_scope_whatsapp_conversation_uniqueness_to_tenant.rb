class ScopeWhatsappConversationUniquenessToTenant < ActiveRecord::Migration[7.1]
  def up
    remove_index :whatsapp_conversations, name: :index_whatsapp_conversations_on_contact_phone if index_exists?(:whatsapp_conversations, :contact_phone, name: :index_whatsapp_conversations_on_contact_phone)
    remove_index :whatsapp_conversations, name: :index_wa_conversations_on_bsuid if index_exists?(:whatsapp_conversations, :business_scoped_user_id, name: :index_wa_conversations_on_bsuid)

    add_index :whatsapp_conversations,
              [:tenant_id, :contact_phone],
              unique: true,
              where: "contact_phone IS NOT NULL",
              name: :index_wa_conversations_on_tenant_and_phone
    add_index :whatsapp_conversations,
              [:tenant_id, :business_scoped_user_id],
              unique: true,
              where: "business_scoped_user_id IS NOT NULL",
              name: :index_wa_conversations_on_tenant_and_bsuid
  end

  def down
    remove_index :whatsapp_conversations, name: :index_wa_conversations_on_tenant_and_phone if index_exists?(:whatsapp_conversations, [:tenant_id, :contact_phone], name: :index_wa_conversations_on_tenant_and_phone)
    remove_index :whatsapp_conversations, name: :index_wa_conversations_on_tenant_and_bsuid if index_exists?(:whatsapp_conversations, [:tenant_id, :business_scoped_user_id], name: :index_wa_conversations_on_tenant_and_bsuid)

    add_index :whatsapp_conversations, :contact_phone, unique: true, name: :index_whatsapp_conversations_on_contact_phone unless index_exists?(:whatsapp_conversations, :contact_phone, name: :index_whatsapp_conversations_on_contact_phone)
    add_index :whatsapp_conversations, :business_scoped_user_id, unique: true, where: "business_scoped_user_id IS NOT NULL", name: :index_wa_conversations_on_bsuid unless index_exists?(:whatsapp_conversations, :business_scoped_user_id, name: :index_wa_conversations_on_bsuid)
  end
end
