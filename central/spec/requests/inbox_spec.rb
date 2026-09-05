require 'rails_helper'
RSpec.describe 'Caixa de atendimento', type: :request do
  it 'abre conversa e envia resposta dentro do frame, mantendo a rota independente' do
    central_login
    ticket = support_ticket
    get '/admin/support/tickets'
    expect(response.body).to include('id="support_queue"', 'id="support_conversation"', 'data-turbo-frame="support_conversation"')
    get "/admin/support/tickets/#{ticket.id}", headers: {'Turbo-Frame'=>'support_conversation'}
    expect(response.body).to include('id="support_conversation"', 'Métricas do chamado')
    post "/admin/support/tickets/#{ticket.id}/messages", params: {body:'Resposta sem sair da fila'}, headers: {'Turbo-Frame'=>'support_conversation'}
    follow_redirect!
    expect(response.body).to include('id="support_conversation"', 'Resposta sem sair da fila')
    get "/admin/support/tickets/#{ticket.id}"
    expect(response).to have_http_status(:ok)
  end

  it 'transporta áudio por conteúdo, oferece player autenticado e bloqueia financeiro' do
    central_login
    ticket = support_ticket
    wav = 'RIFF' + [38].pack('V') + 'WAVEfmt ' + [16,1,1,8000,16000,2,16].pack('VvvVVvv') + 'data' + [2].pack('V') + "\0\0"
    message = Support::Exchange.append_message(ticket, {'uid'=>SecureRandom.uuid, 'side'=>'requester', 'author'=>'Maria', 'body'=>'Áudio', 'files'=>[{'filename'=>'mensagem.wav','data'=>Base64.strict_encode64(wav)}]})
    file = message.files.first
    path = "/admin/support/tickets/#{ticket.id}/attachment?message=#{message.uid}&file=#{file.id}&preview=1"
    get "/admin/support/tickets/#{ticket.id}"
    expect(response.body).to include('<audio controls')
    get path
    expect(response).to have_http_status(:ok)
    expect(response.headers['Content-Disposition']).to start_with('inline')
    expect(response.body.b).to eq(wav.b)
    central_login('financeiro')
    get path
    expect(response).to have_http_status(:forbidden)
  end
end
