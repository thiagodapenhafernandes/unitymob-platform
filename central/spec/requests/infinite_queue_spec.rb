require 'rails_helper'
RSpec.describe 'Fila progressiva e atribuição', type: :request do
  it 'reserva atribuição ao admin, inclusive em encerrados, sem alterar conclusão' do
    agent = central_login
    other = Staff.create!(name:'Outro suporte',email:'other-support@test.example',role:'suporte')
    ticket = support_ticket
    get '/admin/support/tickets'
    expect(response.body).not_to include('data-support-assign')
    patch "/admin/support/tickets/#{ticket.id}",params:{support_ticket:{assignee_id:other.id}}
    expect(response).to have_http_status(:forbidden)
    expect(ticket.reload.assignee_id).to be_nil
    central_login('admin')
    ticket.update!(status:'resolvido', resolved_at:1.hour.ago)
    finished = ticket.resolved_at
    get '/admin/support/tickets'
    expect(response.body).to include('data-support-assign')
    patch "/admin/support/tickets/#{ticket.id}",params:{support_ticket:{assignee_id:other.id}}
    expect(response).to have_http_status(:redirect)
    expect(ticket.reload).to have_attributes(assignee_id:other.id,status:'resolvido',resolved_at:finished)
    expect(Support::Audit.last.details).to have_key('assignee_id')
    patch "/admin/support/tickets/#{ticket.id}",params:{support_ticket:{assignee_id:-1}}
    expect(response).to have_http_status(:unprocessable_entity)
    expect(ticket.reload.assignee_id).to eq(other.id)
  end

  it 'pagina por cursor estável, preserva filtros e não repete cartões' do
    central_login('admin')
    account = support_account
    32.times { support_ticket(account) }
    support_ticket.update!(origin:'ativo')
    get '/admin/support/tickets',params:{origin:'receptivo',order:'newest'}
    doc=Nokogiri::HTML(response.body)
    first_ids=doc.css('[data-support-ticket-link]').map { |a| a['data-support-ticket-link'] }
    expect(first_ids.size).to eq(30)
    next_url=doc.at_css('[data-support-more-link]')['href']
    support_ticket(account) # novo registro não desloca o cursor já emitido
    get next_url,headers:{'Turbo-Frame'=>'support_queue'}
    doc=Nokogiri::HTML(response.body)
    next_ids=doc.css('[data-support-ticket-link]').map { |a| a['data-support-ticket-link'] }
    expect(next_ids.size).to eq(2)
    expect(first_ids & next_ids).to be_empty
    expect(doc.at_css('[data-support-more-link]')).to be_nil
  end
end

RSpec.describe 'Administrador atendente', type: :request do
  it 'pode assumir e responder, preservando autoria e bloqueio após conclusão' do
    admin = central_login('admin')
    ticket = support_ticket
    get '/admin/support/tickets'
    expect(response.body).to include("#{admin.name} · Admin do sistema")
    patch "/admin/support/tickets/#{ticket.id}", params:{support_ticket:{assignee_id:admin.id}}
    expect(response).to have_http_status(:redirect)
    expect(ticket.reload.assignee_id).to eq(admin.id)
    post "/admin/support/tickets/#{ticket.id}/messages",params:{body:'Vou ajudar com esse problema.'}
    expect(response).to have_http_status(:redirect)
    expect(ticket.reload.status).to eq('aguardando_usuario')
    expect(ticket.messages.last).to have_attributes(author_staff_id:admin.id,side:'support')
    ticket.update!(status:'resolvido',resolved_at:Time.current)
    get "/admin/support/tickets/#{ticket.id}"
    expect(Nokogiri::HTML(response.body).at_css('fieldset.ax-support-composer-fields[disabled]')).to be_present
    expect { post "/admin/support/tickets/#{ticket.id}/messages",params:{body:'Não deve enviar'} }.not_to change(Support::Message,:count)
    expect(response).to have_http_status(:unprocessable_entity)
  end
end

RSpec.describe 'Lista completa de responsáveis', type: :request do
  it 'mostra suporte e admin inativos identificados, sem autorizar atribuição a acesso desativado' do
    central_login('admin')
    inactive=Staff.create!(name:'Suporte desativado',email:'inactive-select@test.example',role:'suporte',active:false)
    active=Staff.create!(name:'Suporte ativo',email:'active-select@test.example',role:'suporte',active:true)
    finance=Staff.create!(name:'Financeiro',email:'finance-select@test.example',role:'financeiro')
    ticket=support_ticket
    get '/admin/support/tickets'
    select=Nokogiri::HTML(response.body).at_css('[data-support-assign]')
    option=select.at_css("option[value='#{inactive.id}']")
    expect(option.text).to include('Desativado')
    expect(option['disabled']).to be_present
    expect(select.at_css("option[value='#{active.id}']")['disabled']).to be_nil
    expect(select.at_css("option[value='#{finance.id}']")).to be_nil
    patch "/admin/support/tickets/#{ticket.id}",params:{support_ticket:{assignee_id:inactive.id}}
    expect(response).to have_http_status(:unprocessable_entity)
    expect(ticket.reload.assignee_id).to be_nil
  end
end
