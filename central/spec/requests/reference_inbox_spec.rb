require 'rails_helper'
RSpec.describe 'Atendimento ativo e revisões', type: :request do
  it 'consulta destinatários e abre chamado ativo com destino validado na conta' do
    staff = central_login
    account = support_account
    allow(Support::Transport).to receive(:post).with(account, '/internal/support/v1/recipients', {id:'42'}).and_return('users'=>[{'id'=>'42','name'=>'Maria','email'=>'maria@test.example'}])
    post '/outreach', params:{account_id:account.id, requester_id:'42', outreach_kind:'solicitacao', subject:'Conferir cadastro', body:'Podemos ajudar?'}
    expect(response).to have_http_status(:redirect)
    ticket = account.tickets.last
    expect(ticket).to have_attributes(origin:'ativo', requester_id:'42', status:'aguardando_usuario', assignee_id:staff.id)
    expect(Support::Delivery.last.payload['kind']).to eq('outreach')
    expect(Support::Exchange.wire(Support::Delivery.last).dig('message','body')).to eq('Podemos ajudar?')
    central_login('financeiro')
    get '/outreach/users', params:{account_id:account.id}
    expect(response).to have_http_status(:forbidden)
  end
  it 'edita e remove mensagem própria com auditoria e impede outro operador' do
    author = central_login
    ticket = support_ticket
    message = ticket.messages.create!(side:'support',author:author.name,author_staff_id:author.id,body:'Texto original')
    patch "/admin/support/tickets/#{ticket.id}/revise_message",params:{message_uid:message.uid,body:'Texto corrigido'}
    expect(response).to have_http_status(:redirect)
    expect(message.reload.body).to eq('Texto corrigido')
    expect(Support::Audit.last.details['previous_body']).to eq('Texto original')
    central_login
    delete "/admin/support/tickets/#{ticket.id}/remove_message",params:{message_uid:message.uid}
    expect(response).to have_http_status(:forbidden)
    central_login('admin')
    delete "/admin/support/tickets/#{ticket.id}/remove_message",params:{message_uid:message.uid}
    expect(message.reload.deleted_at).to be_present
    expect(message.revision).to eq(2)
    expect(message.body).to eq('Mensagem removida.')
  end
  it 'filtra origem, destinatário, datas e responsável mantendo tabs e cartões' do
    central_login
    ticket = support_ticket
    ticket.update!(origin:'ativo',requester_email:'unique-recipient@test.example')
    get '/admin/support/tickets',params:{q:'unique-recipient',origin:'ativo',order:'oldest'}
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-support-ticket-link=\"#{ticket.id}\"", 'Abrir chamado ativo')
    get '/admin/support/tickets',params:{q:'unique-recipient',origin:'receptivo'}
    expect(response.body).not_to include("data-support-ticket-link=\"#{ticket.id}\"")
    get '/admin/support/tickets',params:{from:'data-inválida'}
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("data-support-ticket-link=\"#{ticket.id}\"")
  end
end
