class AddInboxAttendanceToWhatsappBusinessIntegrations < ActiveRecord::Migration[7.1]
  def change
    # Botões "WhatsApp" de atendimento (lista de leads, app de campo, clique de
    # push): desligado (padrão) abrem o wa.me externo; ligado, abrem a conversa
    # no inbox interno do sistema. Controlado pelo admin da conta em
    # Configurações → Atendimento WhatsApp.
    add_column :whatsapp_business_integrations, :inbox_attendance_enabled, :boolean, null: false, default: false
  end
end
