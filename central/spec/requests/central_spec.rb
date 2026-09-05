require 'rails_helper'
RSpec.describe 'Central de atendimento', type: :request do
  it 'exige login, inclusive para anexos e operação de chamados' do
    ticket = support_ticket
    get "/admin/support/tickets/#{ticket.id}"
    expect(response).to redirect_to('/login')
  end

  it 'renderiza login, dashboard e fila com o design system compartilhado' do
    get '/login'
    expect(response).to have_http_status(:ok)
    central_login
    get '/'
    expect(response).to have_http_status(:ok)
    get '/admin/support/tickets'
    expect(response.body).to include('Fila de atendimento')
  end

  it 'financeiro não pode ler chamados nem administrar equipe' do
    central_login('financeiro')
    get '/'
    expect(response.body).to include('Financeiro')
    get '/admin/support/tickets'
    expect(response).to have_http_status(:forbidden)
    get '/management'
    expect(response).to have_http_status(:forbidden)
  end

  it 'suporte responde, assume o chamado e envia somente mensagem pública' do
    staff = central_login
    ticket = support_ticket
    post "/admin/support/tickets/#{ticket.id}/notes", params: { body: 'Investigação confidencial' }
    expect(response).to have_http_status(:redirect)
    expect(Support::Delivery.count).to eq(0)
    post "/admin/support/tickets/#{ticket.id}/messages", params: { body: 'Conferimos o cadastro.' }
    expect(response).to have_http_status(:redirect)
    expect(ticket.reload.status).to eq('aguardando_usuario')
    expect(ticket.assignee_id).to eq(staff.id)
    wire = Support::Exchange.wire(Support::Delivery.last)
    expect(wire.to_json).not_to include('Investigação confidencial')
    expect(wire.dig('message','body')).to eq('Conferimos o cadastro.')
    get "/admin/support/tickets/#{ticket.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Notas internas')
  end

  it 'preserva chamado resolvido contra mensagens e alterações' do
    central_login
    ticket = support_ticket
    patch "/admin/support/tickets/#{ticket.id}", params: { support_ticket: { status: 'resolvido' } }
    expect(ticket.reload).to be_resolved
    post "/admin/support/tickets/#{ticket.id}/messages", params: { body: 'Mudar histórico' }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(ticket.messages.count).to eq(0)
    patch "/admin/support/tickets/#{ticket.id}", params: { support_ticket: { status: 'aberto' } }
    expect(ticket.reload).to be_resolved
  end

  it 'admin cria equipe e gerencia contas conectadas automaticamente' do
    central_login('admin')
    post '/management/staff', params: { staff: { name: 'Suporte', email: 'novo@example.test', role: 'suporte' } }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Link de ativação')
    account = support_account
    patch "/management/accounts/#{account.id}", params: { account: { active: false } }
    expect(response).to have_http_status(:redirect)
    expect(account.reload).not_to be_active
    get '/management'
    expect(response.body).to include('conectadas automaticamente')
    expect(response.body).not_to include('Credenciais da conta')
  end

  it 'desativar colaborador invalida sua sessão' do
    staff = central_login
    staff.update!(active: false)
    get '/admin/support/tickets'
    expect(response).to redirect_to('/login')
  end
end
