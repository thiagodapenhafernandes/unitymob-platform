class Support::SlaReport
  attr_reader :metrics, :staff_stats, :summary
  def initialize(tickets:, people:, from:, to:)
    now = Time.current
    events = Support::TicketEvent.where(ticket_id: tickets.select(:id)).order(:occurred_at, :id).to_a.group_by(&:ticket_id)
    @metrics = tickets.select(:id).to_h { |ticket| [ticket.id, Support::Timeline.measure(ticket, events[ticket.id] || [], now: now)] }
    measured = metrics.values.select { |metric| metric[:measured] }
    responses = measured.filter_map { |metric| metric[:first_seconds] }.sort
    resolutions = measured.select { |metric| metric[:resolved_at] }.map { |metric| metric[:total_seconds] }.sort
    @summary = { measured: measured.size, answered: responses.size, resolved: resolutions.size,
      first_average: average(responses), first_p90: percentile(responses), resolution_average: average(resolutions),
      overdue: measured.count { |metric| [metric[:first_sla], metric[:resolution_sla]].include?('Fora do prazo') } }
    sessions = StaffSession.where(staff_id: people.select(:id)).to_a.group_by(&:staff_id)
    windows = StaffPresenceWindow.joins(:staff_session).where(staff_sessions: {staff_id: people.select(:id)})
      .where('confirmed_until >= ? AND staff_presence_windows.started_at <= ?', from, to)
      .pluck('staff_sessions.staff_id', :started_at, :confirmed_until).group_by(&:first)
    actions = Support::TicketEvent.where(ticket_id: tickets.select(:id), staff_id: people.select(:id), occurred_at: from..to).group(:staff_id, :kind, :status).count
    resolved_counts = Support::TicketEvent.where(ticket_id: tickets.select(:id), staff_id: people.select(:id), kind: 'updated', occurred_at: from..to)
      .where("details->'changes'->'status'->>1 = ?", 'resolvido').group(:staff_id).distinct.count(:ticket_id)
    @staff_stats = people.to_h do |staff|
      entries = sessions[staff.id] || []
      waits = measured.flat_map { |metric| metric[:response_waits] }.select { |id, _| id == staff.id }.map(&:last)
      [staff.id, { online: entries.any?(&:online?), seconds: union_seconds(windows[staff.id] || [], from, to),
        logins: entries.count { |entry| (from..to).cover?(entry.started_at) },
        logouts: entries.count { |entry| entry.end_reason == 'logout' && (from..to).cover?(entry.ended_at) },
        responses: actions.sum { |(id, kind, _), count| id == staff.id && kind == 'support_message' ? count : 0 },
        resolved: resolved_counts[staff.id] || 0,
        last_activity: entries.filter_map(&:last_activity_at).max, response_average: average(waits),
        responsibility_seconds: measured.sum { |metric| metric[:owner_seconds][staff.id] || 0 } }]
    end
  end

  private
  def average(values) = values.any? ? values.sum / values.size : nil
  def percentile(values) = values.any? ? values[(values.size * 0.9).ceil - 1] : nil
  def union_seconds(windows, from, to)
    merged = []
    windows.sort_by { |_, left, _| left }.each do |_, left, right|
      left, right = [left, from].max, [right, to].min
      next if right <= left
      if merged.last && left <= merged.last.last
        merged.last[1] = [merged.last.last, right].max
      else
        merged << [left, right]
      end
    end
    merged.sum { |left, right| right - left }.round
  end
end
