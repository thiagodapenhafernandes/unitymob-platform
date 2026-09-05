require 'rails_helper'
RSpec.describe 'Protocolo de chamados', type: :request do
  let(:account) { support_account }
  let(:event) do
    { 'event_id' => SecureRandom.uuid, 'kind' => 'create', 'ticket' => { 'uid' => SecureRandom.uuid, 'requester_id' => '12', 'requester_name' => 'Maria', 'subject' => 'Erro no cadastro', 'intake' => Support::Ticket::QUESTIONS.keys.index_with { 'Detalhes' } }, 'message' => { 'uid' => SecureRandom.uuid, 'body' => 'Preciso de ajuda', 'files' => [] } }
  end
  def send_event(payload, timestamp: Time.current.to_i.to_s, secret: account.secret)
    body = payload.to_json
    post '/internal/support/v1/events', params: body, headers: { 'CONTENT_TYPE' => 'application/json', 'X-Support-Account' => account.uid, 'X-Support-Timestamp' => timestamp, 'X-Support-Signature' => Support::Transport.signature(secret, timestamp, body) }
  end
  it 'recebe criação de outra aplicação e deduplica retry' do
    2.times { send_event(event); expect(response).to have_http_status(:ok) }
    expect(account.tickets.count).to eq(1)
    expect(Support::Message.count).to eq(1)
    expect(Support::Receipt.count).to eq(1)
    expect(Support::Delivery.count).to eq(1)
  end
  it 'rejeita credencial de outra conta e assinatura antiga' do
    send_event(event, secret: 'wrong')
    expect(response).to have_http_status(:unauthorized)
    send_event(event, timestamp: 10.minutes.ago.to_i.to_s)
    expect(response).to have_http_status(:unauthorized)
    expect(Support::Ticket.count).to eq(0)
  end
  it 'não permite injetar prioridade, responsável ou lado suporte pelo cliente' do
    event['ticket']['status'] = 'resolvido'
    event['ticket']['priority'] = 'alta'
    event['message']['side'] = 'support'
    event['message']['author'] = 'Diretor'
    send_event(event)
    expect(response).to have_http_status(:ok)
    expect(Support::Ticket.last.status).to eq('aberto')
    expect(Support::Ticket.last.priority).to eq('normal')
    expect(Support::Message.last.side).to eq('requester')
    expect(Support::Message.last.author).to eq('Maria')
  end
  it 'não aceita mensagem para chamado de outra conta' do
    other = support_ticket
    event['kind'] = 'message'
    event['ticket']['uid'] = other.uid
    send_event(event)
    expect(response).to have_http_status(:conflict)
    expect(other.messages.count).to eq(0)
  end
  it 'rollback preserva retry de payload incompleto' do
    event['ticket']['intake'] = {}
    send_event(event)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Support::Receipt.count).to eq(0)
    expect(Support::Ticket.count).to eq(0)
  end
  it 'recusa anexo disfarçado de PDF' do
    event['message']['files'] = [{ 'filename' => 'arquivo.pdf', 'type' => 'application/pdf', 'data' => Base64.strict_encode64('<script>alert(1)</script>') }]
    send_event(event)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Support::Ticket.count).to eq(0)
  end
end
