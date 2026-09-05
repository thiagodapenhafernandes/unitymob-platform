require 'rails_helper'
RSpec.describe 'Avisos individuais', type: :request do
  it 'conta chamados, lê por colaborador e avisa novamente após resposta' do
    staff = central_login
    ticket = support_ticket
    first = ticket.messages.create!(side:'requester',author:'Maria',body:'Preciso de ajuda')
    get '/notifications', as: :json
    expect(response.parsed_body['count']).to eq(1)
    item = response.parsed_body['items'].first
    expect(item['url']).to include("selected=#{ticket.id}")
    post '/notifications', params:{message_id:first.id}, as: :json
    expect(response).to have_http_status(:no_content)
    get '/notifications', as: :json
    expect(response.parsed_body['count']).to eq(0)
    reply = ticket.messages.create!(side:'requester',author:'Maria',body:'Outra informação')
    ticket.messages.create!(side:'support',author:'Ana',body:'Nota',internal:true)
    get '/notifications', as: :json
    expect(response.parsed_body['count']).to eq(1)
    expect(response.parsed_body['items'].first['kind']).to eq('Nova resposta do cliente')
    post '/notifications', params:{message_id:reply.id}, as: :json
    post '/notifications', params:{message_id:first.id}, as: :json
    expect(SupportNotificationRead.find_by!(staff:staff,ticket:ticket).message_id).to eq(reply.id)
    central_login('admin')
    get '/notifications', as: :json
    expect(response.parsed_body['count']).to eq(1)
    get item['url']
    expect(response.body).to include("data-selected-ticket=\"#{ticket.id}\"")
    ticket.update!(status:'resolvido',resolved_at:Time.current)
    get '/notifications', as: :json
    expect(response.parsed_body['count']).to eq(0)
  end

  it 'bloqueia financeiro e não conta mensagens internas ou de suporte' do
    central_login('financeiro')
    get '/notifications', as: :json
    expect(response).to have_http_status(:forbidden)
    post '/notifications',params:{message_id:1},as: :json
    expect(response).to have_http_status(:forbidden)
    central_login
    ticket=support_ticket
    message=ticket.messages.create!(side:'support',author:'Ana',body:'Mensagem')
    get '/notifications',as: :json
    expect(response.parsed_body['count']).to eq(0)
    post '/notifications',params:{message_id:message.id},as: :json
    expect(response).to have_http_status(:not_found)
  end
end
