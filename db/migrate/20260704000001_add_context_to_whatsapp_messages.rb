class AddContextToWhatsappMessages < ActiveRecord::Migration[7.1]
  def change
    # Reply/citação (menu "Responder"): guarda o wa_message_id da mensagem
    # citada — tanto nas respostas que enviamos (context da Cloud API) quanto
    # nas que o cliente envia respondendo a algo (webhook context.id).
    add_column :whatsapp_messages, :context_wa_message_id, :string
    add_index :whatsapp_messages, :context_wa_message_id
  end
end
