class Support::Timeline
  def self.record!(ticket, kind, staff: nil, details: {})
    policy = SlaPolicy.find_by(priority: ticket.priority)
    details = details.merge('priority' => ticket.priority, 'first_response_minutes' => policy&.first_response_minutes, 'resolution_minutes' => policy&.resolution_minutes) if kind == 'received' || (kind == 'updated' && details.dig('changes', 'priority'))
    Support::TicketEvent.create!(ticket: ticket, staff: staff, kind: kind, status: ticket.status, assignee_id: ticket.assignee_id, occurred_at: Time.current, details: details)
  end

  def self.measure(ticket, events, now: Time.current)
    events = events.sort_by { |e| [e.occurred_at, e.id] }
    received = events.find { |e| e.kind == 'received' }
    return { measured: false } unless received
    resolved = events.find { |e| e.status == 'resolvido' }
    finish = resolved&.occurred_at || now
    response = events.find { |e| e.kind == 'support_message' }
    support_seconds = user_seconds = 0
    owner_seconds = Hash.new(0)
    events.each_with_index do |event, i|
      break if event.occurred_at >= finish || event.status == 'resolvido'
      seconds = [[events[i + 1]&.occurred_at || finish, finish].min - event.occurred_at, 0].max
      if event.status == 'aguardando_usuario'
        user_seconds += seconds
      else
        support_seconds += seconds
        owner_seconds[event.assignee_id] += seconds
      end
    end
    policy = events.reverse.find { |e| e.details.key?('first_response_minutes') }
    first_seconds = response ? response.occurred_at - received.occurred_at : nil
    elapsed = finish - received.occurred_at
    first_target = policy&.details&.dig('first_response_minutes')
    resolution_target = policy&.details&.dig('resolution_minutes')
    pending_since = received.occurred_at
    response_waits = []
    events.each do |event|
      pending_since ||= event.occurred_at if event.kind == 'requester_message'
      if event.kind == 'support_message' && pending_since
        response_waits << [event.staff_id, [event.occurred_at - pending_since, 0].max]
        pending_since = nil
      end
    end
    { response_waits: response_waits, measured: true, received_at: received.occurred_at, resolved_at: resolved&.occurred_at,
      first_seconds: first_seconds, total_seconds: elapsed, support_seconds: support_seconds, user_seconds: user_seconds, owner_seconds: owner_seconds,
      first_sla: resolved && !response ? 'Encerrado sem resposta' : first_target ? ((first_seconds || elapsed) > first_target * 60 ? 'Fora do prazo' : response ? 'No prazo' : 'Dentro do prazo') : 'Sem meta',
      resolution_sla: resolution_target ? (elapsed > resolution_target * 60 ? 'Fora do prazo' : resolved ? 'No prazo' : 'Dentro do prazo') : 'Sem meta' }
  end
end
