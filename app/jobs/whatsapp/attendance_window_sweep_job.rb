module Whatsapp
  # Atendimento sem mensagem do cliente há mais de 24h: a janela de atendimento do WhatsApp já fechou
  # (só templates saem daí), então o atendimento é encerrado e o cliente volta ao menu.
  class AttendanceWindowSweepJob < ApplicationJob
    queue_as :default

    WINDOW = 24.hours

    def perform
      last_inbound = "SELECT MAX(m.created_at) FROM whatsapp_messages m " \
                     "WHERE m.whatsapp_conversation_id = whatsapp_attendances.whatsapp_conversation_id AND m.direction = 'inbound'"
      WhatsappAttendance.open_now
                        .where("COALESCE((#{last_inbound}), whatsapp_attendances.opened_at) < ?", WINDOW.ago)
                        .includes(:whatsapp_conversation, :admin_user)
                        .find_each do |attendance|
        Current.set(tenant: attendance.tenant) { Whatsapp::AttendanceManager.expire!(attendance) }
      end
    end
  end
end
