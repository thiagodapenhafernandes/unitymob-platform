class AddLeadClickActionToPushSettings < ActiveRecord::Migration[7.1]
  def change
    # Destino ao clicar na notificação de novo lead (dentro do prazo):
    # "system" = abre o lead no sistema; "whatsapp" = abre o WhatsApp do lead.
    add_column :push_settings, :lead_click_action, :string, default: "system", null: false
  end
end
