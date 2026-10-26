module Admin::NotificationsHelper
  def notification_origin(kind)
    case kind.to_s
    when /\Ainstagram/ then { label: 'Instagram Direct', icon: 'bi-instagram', tone: 'instagram' }
    when /\Awhatsapp/ then { label: 'WhatsApp', icon: 'bi-whatsapp', tone: 'whatsapp' }
    when 'lead_event', 'lead_notice' then { label: 'Leads', icon: 'bi-person-plus', tone: 'system' }
    else { label: 'Sistema', icon: 'bi-bell', tone: 'system' }
    end
  end

  def notification_event_label(notification)
    case notification.metadata.to_h['event'].presence || notification.kind
    when 'lead_new' then 'Novo lead'
    when 'lead_assigned' then 'Lead atribuído'
    when 'lead_redistributed' then 'Lead redistribuído'
    when 'lead_returned' then 'Lead retornou'
    when 'lead_interest' then 'Novo interesse'
    when 'lead_lost_turn' then 'Prazo de atendimento expirado'
    when 'lead_contingency' then 'Aguardando contingência'
    when 'message_reply' then 'Nova resposta'
    when 'instagram_message', 'whatsapp_message' then 'Nova mensagem'
    when 'attendance_opened' then 'Novo atendimento'
    when 'attendance_transferred' then 'Atendimento transferido'
    when 'attendance_switch_requested' then 'Troca de assunto solicitada'
    when 'attendance_closed' then 'Atendimento encerrado'
    when 'whatsapp_attendance' then notification.title
    when 'whatsapp_task' then 'Nova tarefa'
    when 'portfolio_reassigned' then 'Carteira recebida'
    else 'Aviso'
    end
  end

  # Legados guardam somente o ID: recupera previews em lote, sempre na conta atual.
  def notification_message_previews(notifications, tenant)
    return {} unless tenant

    legacy = notifications.select { |item| item.metadata.to_h['sender_name'].blank? }
    instagram_ids = legacy.filter_map { |item| item.metadata.to_h['instagram_message_id'] }
    whatsapp_ids = legacy.filter_map { |item| item.metadata.to_h['whatsapp_message_id'] }
    instagram = InstagramMessage.joins(:lead).where(leads: { tenant_id: tenant.id }, id: instagram_ids).includes(:lead).index_by(&:id)
    whatsapp = WhatsappMessage.where(tenant_id: tenant.id, id: whatsapp_ids).includes(:whatsapp_conversation).index_by(&:id)
    notifications.to_h do |item|
      metadata = item.metadata.to_h
      message = instagram[metadata['instagram_message_id'].to_i] || whatsapp[metadata['whatsapp_message_id'].to_i]
      message = nil if message.is_a?(InstagramMessage) && message.lead_id.to_s != metadata['lead_id'].to_s
      message = nil if message.is_a?(WhatsappMessage) && message.whatsapp_conversation_id.to_s != metadata['conversation_id'].to_s
      sender = metadata['sender_name'].presence || (message&.is_a?(InstagramMessage) ? message.lead.display_name : message&.whatsapp_conversation&.display_name)
      body = item.body.presence || (message.is_a?(WhatsappMessage) ? message.preview : message&.body)
      [item.id, { sender: sender.presence || item.title, body: body.to_s.truncate(160) }]
    end
  end
end
