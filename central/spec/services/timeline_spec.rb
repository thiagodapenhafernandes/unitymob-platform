require 'rails_helper'
RSpec.describe Support::Timeline do
  it 'mede ciclos reais, separa espera do usuário e preserva metas históricas' do
    travel_to Time.zone.parse('2026-09-05 10:00:00')
    ticket = support_ticket
    staff = Staff.create!(name: 'Operador', email: 'timeline@test.example', role: 'suporte')
    policy = SlaPolicy.create!(priority: 'normal', first_response_minutes: 5, resolution_minutes: 60)
    described_class.record!(ticket, 'received')
    travel 10.minutes
    ticket.update!(status: 'aguardando_usuario', assignee_id: staff.id)
    described_class.record!(ticket, 'support_message', staff: staff)
    travel 20.minutes
    ticket.update!(status: 'em_atendimento')
    described_class.record!(ticket, 'requester_message')
    travel 5.minutes
    policy.update!(first_response_minutes: 100)
    ticket.update!(status: 'resolvido')
    described_class.record!(ticket, 'updated', staff: staff, details: {'changes'=>{'status'=>['em_atendimento','resolvido']}})
    metrics = described_class.measure(ticket, Support::TicketEvent.where(ticket: ticket))
    expect(metrics).to include(first_seconds: 600, total_seconds: 2100, user_seconds: 1200, support_seconds: 900, first_sla: 'Fora do prazo', resolution_sla: 'No prazo')
    expect(metrics[:owner_seconds][staff.id]).to eq(300)
    described_class.record!(ticket, 'updated', staff: staff, details: {'changes'=>{}})
    report = Support::SlaReport.new(tickets: Support::Ticket.all, people: Staff.all, from: 1.day.ago, to: Time.current)
    expect(report.staff_stats[staff.id][:resolved]).to eq(1)
    empty = Support::SlaReport.new(tickets: Support::Ticket.none, people: Staff.all, from: 1.day.ago, to: Time.current)
    expect(empty.staff_stats[staff.id]).to include(resolved: 0, responses: 0)
    travel_back
  end

  it 'não inventa métricas históricas e não duplica presença de sessões simultâneas' do
    ticket = support_ticket
    expect(described_class.measure(ticket, [])).to eq(measured: false)
    staff = Staff.create!(name:'Equipe', email:'presence@test.example', role:'financeiro')
    now = Time.current.change(usec: 0)
    first = staff.staff_sessions.create!(role:staff.role, started_at:now-600, expires_at:now+3600)
    second = staff.staff_sessions.create!(role:staff.role, started_at:now-500, expires_at:now+3600)
    first.presence_windows.create!(started_at:now-600, confirmed_until:now-300)
    second.presence_windows.create!(started_at:now-500, confirmed_until:now-200)
    report = Support::SlaReport.new(tickets: Support::Ticket.all, people: Staff.all, from:now-1000, to:now)
    expect(report.staff_stats[staff.id][:seconds]).to eq(400)
  end
end
