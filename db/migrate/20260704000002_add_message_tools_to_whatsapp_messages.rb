class AddMessageToolsToWhatsappMessages < ActiveRecord::Migration[7.1]
  def change
    # Menu de mensagem estilo WhatsApp:
    # - reações (uma por lado, como no app: cliente e atendente)
    # - fixar / favoritar (recursos internos do CRM)
    # - apagar "para mim" (oculta no CRM; a Cloud API não tem revoke)
    add_column :whatsapp_messages, :client_reaction, :string
    add_column :whatsapp_messages, :agent_reaction, :string
    add_column :whatsapp_messages, :pinned_at, :datetime
    add_column :whatsapp_messages, :starred_at, :datetime
    add_column :whatsapp_messages, :hidden_at, :datetime
    add_index :whatsapp_messages, [:whatsapp_conversation_id, :pinned_at],
              name: "index_whatsapp_messages_on_conversation_pinned"
  end
end
