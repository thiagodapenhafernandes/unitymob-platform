class AddWhatsappSenderNumberToWhatsappConversations < ActiveRecord::Migration[7.1]
  def change
    add_reference :whatsapp_conversations, :whatsapp_sender_number, null: true, index: true,
                  foreign_key: { to_table: :whatsapp_sender_numbers, on_delete: :nullify }
  end
end
