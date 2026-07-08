class AddPresentationCardToWhatsappMessages < ActiveRecord::Migration[7.1]
  def change
    # Nullable: só mensagens originadas de cartão de apresentação carregam o
    # carimbo. Auditoria consultável (remetente + card + conversa + created_at)
    # sem tabela nova, com ou sem lead.
    add_reference :whatsapp_messages, :presentation_card, null: true, foreign_key: true, index: true
  end
end
