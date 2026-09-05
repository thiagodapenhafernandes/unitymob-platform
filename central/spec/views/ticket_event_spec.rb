require 'rails_helper'

RSpec.describe 'admin/shared/ui/_support_ticket_event', type: :view do
  it 'apresenta ação, autoria, mudanças reais e data sem confundir resposta com entrega' do
    ticket = support_ticket
    staff = Staff.create!(name: 'Ana', email: 'event@test.example', role: 'suporte')
    event = Support::Timeline.record!(ticket, 'updated', staff: staff, details: {
      'changes' => { 'status' => ['aberto', 'em_atendimento'], 'assignee_id' => [nil, staff.id] }
    })
    render partial: 'admin/shared/ui/support_ticket_event', locals: { event: event, ticket: ticket, staff_names: { staff.id => staff.name } }
    expect(rendered).to include('Atendimento atualizado', 'Ana', 'Aberto → Em atendimento', 'Sem responsável → Ana', 'datetime=')
    expect(rendered).not_to include('Conta de origem')

    response_event = Support::Timeline.record!(ticket, 'support_message', staff: staff)
    expect(view.support_event_title(response_event)).to eq('Resposta do suporte registrada')
    requester_event = Support::Timeline.record!(ticket, 'requester_message')
    expect(view.support_event_actor(requester_event, ticket)).to eq('Maria · Salute')
  end
end
