# Consultas do painel: fila atual separada da coorte recebida nos últimos 30 dias.
class Support::OperationsDashboard
  attr_reader :now, :counts, :open_tickets, :metrics, :overdue_ids, :on_time_ids, :unmeasured_ids,
    :attention, :report, :people, :accounts, :received_today, :resolved_today, :pending, :failed,
    :account_load, :staff_load, :staff_overdue, :account_overdue

  def initialize(admin:)
    @now = Time.current
    @counts = Support::Ticket.group(:status).count
    @open_tickets = Support::Ticket.where.not(status: 'resolvido').includes(:account).order(:created_at).to_a
    events = Support::TicketEvent.where(ticket_id: open_tickets.map(&:id)).order(:occurred_at, :id).to_a.group_by(&:ticket_id)
    @metrics = open_tickets.to_h { |ticket| [ticket.id, Support::Timeline.measure(ticket, events[ticket.id] || [], now: now)] }
    @overdue_ids = metrics.select { |_, m| m[:measured] && [m[:first_sla], m[:resolution_sla]].include?('Fora do prazo') }.keys
    @on_time_ids = metrics.select { |_, m| m[:measured] && ![m[:first_sla], m[:resolution_sla]].any? { |s| ['Fora do prazo', 'Sem meta'].include?(s) } }.keys
    @unmeasured_ids = metrics.keys - overdue_ids - on_time_ids
    @attention = open_tickets.sort_by { |t| [overdue_ids.include?(t.id) ? 0 : t.assignee_id.nil? ? 1 : 2, t.created_at] }.first(10)
    @people = admin ? Staff.where(active: true).order(:name) : Staff.none
    received = Support::TicketEvent.where(kind: 'received', occurred_at: (now - 30.days)..now)
    @report = Support::SlaReport.new(tickets: Support::Ticket.where(id: received.select(:ticket_id)), people: people, from: now - 30.days, to: now)
    @received_today = received.where(occurred_at: now.beginning_of_day..now).distinct.count(:ticket_id)
    @resolved_today = Support::TicketEvent.where(kind: 'updated', occurred_at: now.beginning_of_day..now)
      .where("details->'changes'->'status'->>1 = ?", 'resolvido').distinct.count(:ticket_id)
    @pending = Support::Delivery.where(delivered_at: nil, failed_at: nil).count
    @failed = Support::Delivery.where(delivered_at: nil).where.not(failed_at: nil).count
    @accounts = admin ? Support::Account.order(:name).to_a : []
    @account_load = open_tickets.group_by(&:account_id)
    @staff_load = open_tickets.group_by(&:assignee_id)
    overdue = open_tickets.select { |t| overdue_ids.include?(t.id) }
    @staff_overdue = overdue.group_by(&:assignee_id)
    @account_overdue = overdue.group_by(&:account_id)
  end

  def waiting_support = counts.fetch('aberto', 0) + counts.fetch('em_atendimento', 0)
  def unassigned = open_tickets.count { |t| t.assignee_id.nil? }
  def online_support = people.count { |s| s.role == 'suporte' && report.staff_stats.fetch(s.id)[:online] }
end
