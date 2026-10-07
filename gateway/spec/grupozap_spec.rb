require 'spec_helper'

RSpec.describe 'Grupo OLX Gateway' do
  def app
    Gateway::App
  end
  let(:key) { '9e9c2c58-5696-466f-a251-02bb5f7ee7ea' }
  let(:target) { "https://crm.example.com/webhooks/portal_leads/grupozap/#{key}" }
  let(:payload) { {originLeadId: 'lead-1', clientListingId: 'AP-1'} }
  before { ENV['GRUPOZAP_SECRET_KEY'] = 'olx-secret' }
  after { ENV.delete('GRUPOZAP_SECRET_KEY') }

  def register(active = true)
    post '/internal/grupozap/routes', {client_key: key, tenant_name: 'Cliente', target_url: target,
      forwarding_secret: 's' * 32, active: active}.to_json,
      {'HTTP_AUTHORIZATION' => 'Bearer internal-token', 'CONTENT_TYPE' => 'application/json'}
  end

  def receive(key_value = key, password = 'olx-secret')
    post "/webhooks/grupozap/#{key_value}", payload.to_json,
      {'HTTP_AUTHORIZATION' => "Basic #{['vivareal:' + password].pack('m0')}", 'CONTENT_TYPE' => 'application/json'}
  end

  it 'registers idempotently and forwards with an integration-bound signature' do
    register
    register
    expect(WebhookRoute.where(provider: 'grupozap').count).to eq(1)
    signature = Gateway::InternalSignature.sign("#{key}\n#{payload.to_json}", secret: 's' * 32)
    stub = stub_request(:post, target).with(headers: {'X-Unitymob-Gateway-Signature' => signature}).to_return(status: 200)
    receive
    expect(last_response.status).to eq(200)
    receive
    expect(stub).to have_been_requested.once
    expect(WebhookEvent.last.status).to eq('forwarded')
  end

  it 'persists failure and delivers using existing retry' do
    register
    stub_request(:post, target).to_return(status: 503)
    receive
    expect(last_response.status).to eq(200)
    expect(WebhookEvent.last.status).to eq('failed')
    stub_request(:post, target).to_return(status: 200)
    Gateway::RetryFailedEvents.call(now: Time.now + 60)
    expect(WebhookEvent.last.status).to eq('forwarded')
  end

  it 'rejects authentication, unknown identifiers and paused routes' do
    register
    receive(key, 'wrong')
    expect(last_response.status).to eq(401)
    receive('unknown')
    expect(last_response.status).to eq(404)
    register(false)
    receive
    expect(last_response.status).to eq(404)
    expect(WebhookEvent.count).to eq(0)
  end

  it 'does not register without internal authentication' do
    post '/internal/grupozap/routes', '{}'
    expect(last_response.status).to eq(401)
  end

  it 'recovers a delivery persisted before a gateway interruption' do
    register
    route = WebhookRoute.find_by!(provider: 'grupozap', client_key: key)
    event = WebhookEvent.create!(provider: 'grupozap', webhook_route: route, external_id: 'interrupted',
      event_type: 'lead', raw_body: payload.to_json, payload: payload, status: 'received', received_at: Time.now - 120)
    stub_request(:post, target).to_return(status: 200)
    Gateway::RetryFailedEvents.call
    expect(event.reload.status).to eq('forwarded')
  end
end
