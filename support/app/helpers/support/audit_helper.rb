module Support::AuditHelper
  def support_event_title(event)
    { 'received' => 'Chamado recebido pela central',
      'requester_message' => 'Mensagem do usuário recebida',
      'support_message' => 'Resposta do suporte registrada',
      'internal_note' => 'Nota interna adicionada',
      'updated' => 'Atendimento atualizado' }[event.kind] || 'Evento registrado'
  end

  def support_event_actor(event, ticket)
    return event.staff.name if event.staff
    return 'Colaborador não disponível' if event.staff_id
    return [ticket.requester_name, ticket.account.name].join(' · ') if event.kind == 'requester_message'
    event.kind == 'received' ? "Conta: #{ticket.account.name}" : 'Autor não registrado'
  end

  def support_audit_action(action)
    {'ticket_updated'=>'Atendimento atualizado', 'access_requested'=>'Acesso à conta solicitado',
     'message_edited'=>'Mensagem editada', 'message_removed'=>'Mensagem removida'}[action] || 'Alteração registrada'
  end

  def support_audit_actor(actor, names)
    return names[actor.delete_prefix('staff:').to_i] || 'Colaborador não disponível' if actor.to_s.start_with?('staff:')
    actor.to_s.start_with?('user:') ? 'Usuário da conta' : 'Sistema'
  end

  def support_audit_value(key, value, names)
    case key
    when 'status' then Support::Ticket::STATUS_LABELS[value] || 'Não informado'
    when 'priority' then {'alta'=>'Alta','normal'=>'Normal','baixa'=>'Baixa'}[value] || 'Não informada'
    when 'assignee_id' then value.present? ? names[value.to_i] || 'Colaborador não disponível' : 'Sem responsável'
    else value.presence || 'Nenhuma'
    end
  end
end
