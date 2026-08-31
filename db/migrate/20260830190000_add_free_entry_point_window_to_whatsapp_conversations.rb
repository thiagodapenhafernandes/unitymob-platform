class AddFreeEntryPointWindowToWhatsappConversations < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_conversations, :free_entry_point_expires_at, :datetime
  end
end
