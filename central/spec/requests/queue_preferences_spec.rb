require 'rails_helper'
RSpec.describe 'Preferências pessoais da fila',type: :request do
  it 'persiste por usuário sem contaminar links de chamados ou de indicadores' do
    staff=central_login
    prefs={status:'em_atendimento',origin:'receptivo',mine:'1',order:'newest'}
    patch '/queue_preferences',params:{preferences:prefs},as: :json
    expect(response).to have_http_status(:no_content)
    expect(staff.reload.queue_preferences).to eq(prefs.stringify_keys)
    get '/admin/support/tickets'
    expect(response).to have_http_status(:redirect)
    follow_redirect!
    expect(response.body).to include('value="newest"')
    ticket=support_ticket
    get '/admin/support/tickets',params:{q:"##{ticket.id}",selected:ticket.id}
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-support-ticket-link=\"#{ticket.id}\"")
    central_login('admin')
    get '/admin/support/tickets'
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('value="oldest"')
  end
  it 'rejeita valores inválidos e financeiro' do
    staff=central_login
    patch '/queue_preferences',params:{preferences:{status:'invalid',origin:'',mine:'',order:'newest'}},as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(staff.reload.queue_preferences).to eq({})
    central_login('financeiro')
    patch '/queue_preferences',params:{preferences:{status:'',origin:'',mine:'',order:'oldest'}},as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
