require 'spec_helper'

RSpec.describe 'Imovelweb self-service Gateway' do
  def app
    Gateway::App
  end
  let(:key) { SecureRandom.uuid }
  let(:code) { "um-#{SecureRandom.uuid}" }
  let(:client) { instance_double(Gateway::ImovelwebClient) }
  let(:headers) { {'HTTP_AUTHORIZATION' => 'Bearer internal-token', 'CONTENT_TYPE' => 'application/json'} }
  let(:data) { {client_key: key, client_code: code, environment: 'production', target_url: "https://crm.example.com/webhooks/imovelweb/#{key}", forwarding_secret: 's' * 32, active: true, advertiser_code: '47294717'} }
  before do
    allow(Gateway::ImovelwebClient).to receive(:new).with(environment: 'production').and_return(client)
    allow(client).to receive(:authorized_advertiser).with(client_code: code).and_return(client_code: code, advertiser_code: '47294717')
  end

  it 'authenticates and validates before contacting the provider' do
    post '/internal/imovelweb/verification', {environment: 'production', client_code: code}.to_json, {'CONTENT_TYPE' => 'application/json'}
    expect(last_response.status).to eq(401)
    post '/internal/imovelweb/verification', {environment: 'other', client_code: code}.to_json, headers
    expect(last_response.status).to eq(422)
    expect(client).not_to have_received(:authorized_advertiser)
  end

  it 'returns only the requested identity without creating any route' do
    post '/internal/imovelweb/verification', {environment: 'production', client_code: code}.to_json, headers
    expect(JSON.parse(last_response.body)).to eq('confirmed' => true, 'advertiser_code' => '47294717')
    expect(WebhookRoute.count).to eq(0)
    allow(client).to receive(:authorized_advertiser).and_return(nil)
    post '/internal/imovelweb/verification', {environment: 'production', client_code: code}.to_json, headers
    expect(JSON.parse(last_response.body)).to eq('confirmed' => false, 'advertiser_code' => nil)
  end

  it 'registers a confirmed branch idempotently and refuses reuse by another CRM' do
    2.times do
      post '/internal/imovelweb/routes', data.to_json, headers
      expect(last_response.status).to eq(200)
    end
    expect(WebhookRoute.count).to eq(1)
    expect(WebhookRoute.last.imovelweb_advertiser_code).to eq('47294717')
    other_code = "um-#{SecureRandom.uuid}"
    allow(client).to receive(:authorized_advertiser).with(client_code: other_code).and_return(client_code: other_code, advertiser_code: '47294717')
    other_key = SecureRandom.uuid
    post '/internal/imovelweb/routes', data.merge(client_key: other_key, client_code: other_code, target_url: "https://other.example.com/webhooks/imovelweb/#{other_key}").to_json, headers
    expect(last_response.status).to eq(409)
    expect(WebhookRoute.count).to eq(1)
  end

  it 'protects existing legacy numeric routes' do
    WebhookRoute.create!(provider: 'imovelweb', client_key: SecureRandom.uuid, imovelweb_environment: 'production', imovelweb_client_code: '47294717', target_url: 'https://legacy.example.com', forwarding_secret: 's' * 32)
    post '/internal/imovelweb/routes', data.to_json, headers
    expect(last_response.status).to eq(409)
    expect(WebhookRoute.count).to eq(1)
  end

  it 'rejects absent consent and sanitizes provider failures' do
    allow(client).to receive(:authorized_advertiser).and_return(nil)
    post '/internal/imovelweb/routes', data.to_json, headers
    expect(last_response.status).to eq(409)
    expect(WebhookRoute.count).to eq(0)
    allow(client).to receive(:authorized_advertiser).and_raise(Gateway::ImovelwebClient::Error, 'private credentials')
    post '/internal/imovelweb/verification', {environment: 'production', client_code: code}.to_json, headers
    expect(last_response.status).to eq(503)
    expect(last_response.body).not_to include('private credentials')
  end
end

RSpec.describe 'Imovelweb listing preparation routing' do
  def app
    Gateway::App
  end
  it 'does not prepare ads without an active route belonging to the exact connection' do
    client = instance_double(Gateway::ImovelwebClient)
    expect(client).not_to receive(:associate_online_listings)
    post '/internal/imovelweb/listings', {client_key: SecureRandom.uuid, client_code: 'unknown', environment: 'production', page: 0}.to_json, {'HTTP_AUTHORIZATION' => 'Bearer internal-token', 'CONTENT_TYPE' => 'application/json'}
    expect(last_response.status).to eq(404)
  end
end

RSpec.describe 'Imovelweb listing preparation batch' do
  def app
    Gateway::App
  end
  it 'delegates only the exact active route and forwards the next page without modifying the route' do
    key = SecureRandom.uuid
    route = WebhookRoute.create!(provider: 'imovelweb', client_key: key, imovelweb_environment: 'production', imovelweb_client_code: 'owned', target_url: 'https://owned.example.com', forwarding_secret: 's' * 32)
    client = instance_double(Gateway::ImovelwebClient)
    allow(Gateway::ImovelwebClient).to receive(:new).with(environment: 'production').and_return(client)
    expect(client).to receive(:associate_online_listings).with(client_code: 'owned', page: 0).and_return(associated: 2, next_page: 1)
    before = route.attributes
    post '/internal/imovelweb/listings', {client_key: key, client_code: 'owned', environment: 'production', page: 0}.to_json, {'HTTP_AUTHORIZATION' => 'Bearer internal-token', 'CONTENT_TYPE' => 'application/json'}
    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to eq('associated' => 2, 'next_page' => 1)
    expect(route.reload.attributes).to eq(before)
  end
end
