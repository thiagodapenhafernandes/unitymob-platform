class AddWhatsappConversationsInboxQueueIndex < ActiveRecord::Migration[7.1]
  # Fila do inbox WhatsApp (load_inbox roda em todo index/show sem turbo-frame):
  # - conversation_scope.recent.limit(200) = WHERE tenant_id = ?
  #   ORDER BY last_message_at DESC NULLS LAST, updated_at DESC — o índice
  #   composto abaixo casa com o ORDER BY e permite parar no LIMIT;
  # - conversation_scope.unread.sum(:unread_count) = WHERE tenant_id = ? AND
  #   unread_count > 0 — parcial com unread_count na chave (sum index-only).
  RECENT_INDEX = "idx_wa_conversations_on_tenant_recent".freeze
  UNREAD_INDEX = "idx_wa_conversations_on_tenant_unread".freeze

  def up
    unless index_exists?(:whatsapp_conversations, [:tenant_id, :last_message_at, :updated_at], name: RECENT_INDEX)
      add_index :whatsapp_conversations, [:tenant_id, :last_message_at, :updated_at],
                order: { last_message_at: "DESC NULLS LAST", updated_at: "DESC" },
                name: RECENT_INDEX
    end

    unless index_exists?(:whatsapp_conversations, [:tenant_id, :unread_count], name: UNREAD_INDEX)
      add_index :whatsapp_conversations, [:tenant_id, :unread_count],
                where: "unread_count > 0", name: UNREAD_INDEX
    end
  end

  def down
    if index_exists?(:whatsapp_conversations, [:tenant_id, :unread_count], name: UNREAD_INDEX)
      remove_index :whatsapp_conversations, name: UNREAD_INDEX
    end
    if index_exists?(:whatsapp_conversations, [:tenant_id, :last_message_at, :updated_at], name: RECENT_INDEX)
      remove_index :whatsapp_conversations, name: RECENT_INDEX
    end
  end
end
