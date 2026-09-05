require 'rails_helper'
RSpec.describe 'Painel operacional', type: :request do
  it 'distingue fila, atrasos, falta de medição e histórico sem expor equipe ao suporte' do
    central_login('admin')
    now = Time.current.change(usec: 0)
    travel_to now
    SlaPolicy.create!(priority: 'normal', first_response_minutes: 1, resolution_minutes: 10)
    late = support_ticket
    travel_to now - 2.minutes
    Support::Timeline.record!(late, 'received')
    travel_to now
    timely = support_ticket
    Support::Timeline.record!(timely, 'received')
    unknown = support_ticket
    waiting = support_ticket
    waiting.update!(status: 'aguardando_usuario')
    Support::Timeline.record!(waiting, 'received')
    waiting.update!(subject: 'Aguardando retorno exclusivo')
    closed = support_ticket
    closed.update!(status: 'resolvido')
    d = Support::OperationsDashboard.new(admin: true)
    expect(d.waiting_support).to eq(3)
    expect(d.overdue_ids).to eq([late.id])
    expect(d.on_time_ids).to contain_exactly(timely.id, waiting.id)
    expect(d.unmeasured_ids).to eq([unknown.id])
    expect(d.attention.first).to eq(late)
    expect(d.open_tickets).not_to include(closed)
    get '/'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Equipe agora', 'Contas e comunicação', 'Esperando o suporte', 'Sem medição')
    get '/admin/support/tickets', params: { queue: 'waiting_support' }
    expect(response.body).not_to include('Aguardando retorno exclusivo')
    central_login('suporte')
    get '/'
    expect(response.body).not_to include('Equipe agora', 'Contas e comunicação')
    travel_back
  end

  it 'apresenta duração sem frações de horas e separa falha definitiva de envio em espera' do
    helper = Object.new.extend(SlaHelper)
    expect(helper.sla_duration(3665)).to eq('1h 1min 5s')
    expect(helper.sla_duration(268)).to eq('4min 28s')
    expect(helper.sla_duration(nil)).to eq('Sem medição')
    account = support_account
    Support::Delivery.create!(account: account, payload: {}, failed_at: Time.current)
    Support::Delivery.create!(account: account, payload: {})
    dashboard = Support::OperationsDashboard.new(admin: true)
    expect(dashboard.pending).to eq(1)
    expect(dashboard.failed).to eq(1)
  end
end
