class AddVcardEnabledToLeadSettings < ActiveRecord::Migration[7.1]
  def change
    # Cartão de contato (vCard) do lead por conta: botão "Salvar contato" na
    # ficha + variável lead_vcard_or_link no WhatsApp da distribuição.
    add_column :lead_settings, :vcard_enabled, :boolean, default: false, null: false
  end
end
