require 'rails_helper'

RSpec.describe Admin::NotificationsHelper, type: :helper do
  it 'distingue contexto, origem e leitura, com fallback seguro para legados' do
    {
      'lead_new' => 'Novo lead', 'lead_assigned' => 'Lead atribuído',
      'lead_redistributed' => 'Lead redistribuído', 'lead_returned' => 'Lead retornou',
      'lead_interest' => 'Novo interesse', 'lead_lost_turn' => 'Prazo de atendimento expirado',
      'lead_contingency' => 'Aguardando contingência', 'message_reply' => 'Nova resposta',
      'attendance_opened' => 'Novo atendimento', 'attendance_transferred' => 'Atendimento transferido',
      'attendance_switch_requested' => 'Troca de assunto solicitada', 'attendance_closed' => 'Atendimento encerrado'
    }.each do |event, label|
      notice = InAppNotification.new(kind: 'notice', title: 'Aviso', metadata: { event: event })
      expect(helper.notification_event_label(notice)).to eq(label)
      notice.read_at = Time.current
      expect(helper.notification_event_label(notice)).to eq(label)
    end
    { 'instagram_message' => 'Nova mensagem', 'whatsapp_message' => 'Nova mensagem',
      'whatsapp_task' => 'Nova tarefa', 'portfolio_reassigned' => 'Carteira recebida',
      'unknown' => 'Aviso', 'whatsapp_attendance' => 'Atendimento transferido' }.each do |kind, label|
      expect(helper.notification_event_label(InAppNotification.new(kind: kind, title: 'Atendimento transferido'))).to eq(label)
    end
  end
end
