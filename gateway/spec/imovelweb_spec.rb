require 'spec_helper'

RSpec.describe 'Imovelweb Gateway' do
  def app
    Gateway::App
  end
  let(:key) { SecureRandom.uuid }
  let(:target) { "https://crm.example.com/webhooks/imovelweb/#{key}" }
  let(:payload) { {eventId: 'event-1', eventType: 'CONTACTO_MENSAJE', clientCode: 'unitymob-client', reference: 'AP-1', email: 'lead@example.com', name: 'Cliente', identificationId: 'must-not-store'} }
  before do
    @previous = ENV.to_h.slice('IMOVELWEB_RECEIVING_ENABLED', 'IMOVELWEB_SANDBOX_CALLBACK_TOKEN', 'GATEWAY_ASYNC_DELIVERY_ENABLED')
    ENV['IMOVELWEB_RECEIVING_ENABLED'] = 'true'
    ENV['IMOVELWEB_SANDBOX_CALLBACK_TOKEN'] = 't' * 32
    ENV['GATEWAY_ASYNC_DELIVERY_ENABLED'] = 'true'
  end
  after do
    %w[IMOVELWEB_RECEIVING_ENABLED IMOVELWEB_SANDBOX_CALLBACK_TOKEN GATEWAY_ASYNC_DELIVERY_ENABLED].each { |key| @previous.key?(key) ? ENV[key] = @previous[key] : ENV.delete(key) }
  end

  def register(active = true, code = 'unitymob-client')
    post '/internal/imovelweb/routes', {client_key: key, client_code: code, environment: 'sandbox', target_url: target,
      forwarding_secret: 's' * 32, active: active}.to_json,
      {'HTTP_AUTHORIZATION' => 'Bearer internal-token', 'CONTENT_TYPE' => 'application/json'}
  end

  def receive(token = 't' * 32)
    post '/webhooks/imovelweb/sandbox', payload.to_json,
      {'HTTP_AUTHORIZATION' => "Bearer #{token}", 'CONTENT_TYPE' => 'application/json'}
  end

  it 'persists once, acknowledges before delivery and signs normalized data for the owning connection' do
    register
    expect(last_response.status).to eq(200)
    receive
    expect(last_response.status).to eq(202)
    event = WebhookEvent.last
    expect(event.status).to eq('received')
    expect(event.raw_body).not_to include('must-not-store')
    receive
    expect(WebhookEvent.count).to eq(1)
    body = event.raw_body
    signature = Gateway::InternalSignature.sign("#{key}\n#{body}", secret: 's' * 32)
    stub = stub_request(:post, target).with(body: body, headers: {'X-Unitymob-Gateway-Signature' => signature, 'X-Unitymob-Gateway-Provider' => 'imovelweb'}).to_return(status: 200)
    Gateway::DeliveryWorker.tick
    expect(event.reload.status).to eq('forwarded')
    Gateway::DeliveryWorker.tick
    expect(stub).to have_been_requested.once
  end

  it 'keeps first event body even if a redelivery changes its fields' do
    register
    receive
    payload[:message] = 'changed'
    payload[:eventType] = 'CONTACTO'
    receive
    expect(last_response.status).to eq(202)
    expect(WebhookEvent.count).to eq(1)
    expect(WebhookEvent.last.payload).not_to have_key('message')
  end

  it 'fails closed for auth, unknown accounts, disabled routes and environments' do
    register
    receive('wrong')
    expect(last_response.status).to eq(401)
    payload[:clientCode] = 'unknown'
    receive
    expect(last_response.status).to eq(404)
    payload[:clientCode] = 'unitymob-client'
    register(false)
    receive
    expect(last_response.status).to eq(404)
    ENV.delete('IMOVELWEB_RECEIVING_ENABLED')
    receive
    expect(last_response.status).to eq(503)
    expect(WebhookEvent.count).to eq(0)
  end

  it 'rejects missing or conflicting routing identity and non-lead events' do
    register
    payload[:codigoImobiliaria] = 'different'
    receive
    expect(last_response.status).to eq(422)
    payload.delete(:codigoImobiliaria)
    payload[:eventType] = 'AVISO_ACTIVIDAD'
    receive
    expect(last_response.status).to eq(422)
    payload[:eventType] = 'CONTACTO'
    payload.delete(:clientCode)
    receive
    expect(last_response.status).to eq(422)
    expect(WebhookEvent.count).to eq(0)
  end

  it 'retries a failed delivery asynchronously without changing OLX delivery' do
    register
    receive
    event = WebhookEvent.last
    stub_request(:post, target).to_return(status: 503)
    Gateway::DeliveryWorker.tick
    expect(event.reload.status).to eq('failed')
    event.update!(next_retry_at: Time.now - 1)
    event.delivery_destination.update!(available_at: Time.now - 1)
    stub_request(:post, target).to_return(status: 200)
    Gateway::DeliveryWorker.tick
    expect(event.reload.status).to eq('forwarded')
  end

  it 'holds accepted receipts durably while the Imovelweb switch is off' do
    register
    receive
    event = WebhookEvent.last
    ENV.delete('IMOVELWEB_RECEIVING_ENABLED')
    expect(Gateway::DeliveryWorker.tick).to eq(0)
    expect(event.reload.status).to eq('received')
    expect(event.attempts).to eq(0)
    ENV['IMOVELWEB_RECEIVING_ENABLED'] = 'true'
    stub_request(:post, target).to_return(status: 200)
    Gateway::DeliveryWorker.tick
    expect(event.reload.status).to eq('forwarded')
  end

  it 'routes identical listing codes by client identity, never by property alone' do
    register
    other_key = SecureRandom.uuid
    other = WebhookRoute.create!(provider: 'imovelweb', client_key: other_key, imovelweb_client_code: 'second-client', imovelweb_environment: 'sandbox',
      target_url: "https://other.example.com/webhooks/imovelweb/#{other_key}", forwarding_secret: 'x' * 32, active: true)
    receive
    first = WebhookEvent.last
    payload[:clientCode] = 'second-client'
    receive
    second = WebhookEvent.last
    expect(first.webhook_route_id).not_to eq(second.webhook_route_id)
    expect(second.webhook_route_id).to eq(other.id)
    expect(WebhookEvent.count).to eq(2)
  end

  it 'protects internal registration and route identity' do
    post '/internal/imovelweb/routes', '{}'
    expect(last_response.status).to eq(401)
    register
    register(true, 'other-client')
    expect(last_response.status).to eq(409)
    expect(WebhookRoute.last.imovelweb_client_code).to eq('unitymob-client')
  end
end

RSpec.describe Gateway::ImovelwebPayload do
  it 'normalizes Portuguese fields and preserves event identity independently of contact identity' do
    result = described_class.normalize({'idEvento' => 'event', 'tipoEvento' => 'CONTACTO', 'codigoImobiliaria' => 'client', 'nome' => 'Nome', 'telefone' => '+5511999999999', 'idContato' => nil})
    expect(result).to include('event_id' => 'event', 'client_code' => 'client', 'phone' => '+5511999999999')
    expect(result).not_to have_key('idContato')
  end
end
