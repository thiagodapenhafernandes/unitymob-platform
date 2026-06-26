class AddBusinessScopedUserIds < ActiveRecord::Migration[7.1]
  def up
    # BSUID (user_id da Meta): identidade estável do usuário no escopo da WABA,
    # independente do telefone. Capturado dos webhooks (contacts[].user_id) para
    # não perder leads que escondem o número (recurso de username da Meta).
    add_column :whatsapp_conversations, :business_scoped_user_id, :string
    add_index :whatsapp_conversations, :business_scoped_user_id,
              unique: true, where: "business_scoped_user_id IS NOT NULL",
              name: "index_wa_conversations_on_bsuid"

    # Conversa pode existir só com BSUID (sem telefone visível).
    change_column_null :whatsapp_conversations, :contact_phone, true

    add_column :leads, :business_scoped_user_id, :string
    add_index :leads, :business_scoped_user_id, where: "business_scoped_user_id IS NOT NULL",
              name: "index_leads_on_bsuid"

    # Destinatário por BSUID nos webhooks de status (statuses[].recipient_user_id).
    add_column :whatsapp_messages, :recipient_user_id, :string
  end

  def down
    remove_index :whatsapp_conversations, name: "index_wa_conversations_on_bsuid"
    remove_column :whatsapp_conversations, :business_scoped_user_id
    change_column_null :whatsapp_conversations, :contact_phone, false
    remove_index :leads, name: "index_leads_on_bsuid"
    remove_column :leads, :business_scoped_user_id
    remove_column :whatsapp_messages, :recipient_user_id
  end
end
