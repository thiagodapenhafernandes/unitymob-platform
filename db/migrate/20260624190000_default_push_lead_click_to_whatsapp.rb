class DefaultPushLeadClickToWhatsapp < ActiveRecord::Migration[7.1]
  def up
    # Padrão operacional: o clique no push abre a conversa do WhatsApp do lead.
    change_column_default :push_settings, :lead_click_action, from: nil, to: "whatsapp"
    # Promove configurações já existentes que ainda estavam em "system".
    execute "UPDATE push_settings SET lead_click_action = 'whatsapp' WHERE lead_click_action IS NULL OR lead_click_action = 'system'"
  end

  def down
    change_column_default :push_settings, :lead_click_action, from: "whatsapp", to: nil
  end
end
