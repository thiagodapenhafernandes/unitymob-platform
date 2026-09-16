require_relative 'spec_helper'

RSpec.describe 'Meta destination isolation' do
  include Rack::Test::Methods
  def app
    Gateway::App
  end

  it 'rejects another client or target for the same page, including another form' do
    route = WebhookRoute.create!(provider: 'meta', client_key: 'salute', page_id: '100', target_url: 'https://salute.test/webhooks/meta', forwarding_secret: 'secret')
    [{client_key: 'conexao'}, {target_url: 'https://conexao.test/webhooks/meta'}, {client_key: 'conexao', form_id: '200'}].each do |change|
      payload = route.attributes.slice('client_key', 'page_id', 'target_url', 'forwarding_secret').merge(change.stringify_keys)
      post '/internal/meta/routes', payload.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer internal-token'
      expect(last_response.status).to eq(409)
      expect(route.reload.target_url).to eq('https://salute.test/webhooks/meta')
      expect(WebhookRoute.count).to eq(1)
    end
  end

  it 'updates legacy default client key when the destination is unchanged' do
    WebhookRoute.create!(provider: 'meta', client_key: 'default', page_id: '100', target_url: 'https://salute.test/webhooks/meta', forwarding_secret: 'secret')
    WebhookRoute.create!(provider: 'meta', client_key: 'default', page_id: '100', form_id: '200', target_url: 'https://salute.test/webhooks/meta', forwarding_secret: 'secret')
    payload = {
      client_key: 'salute-test',
      tenant_name: 'Salute',
      page_id: '100',
      target_url: 'https://salute.test/webhooks/meta',
      forwarding_secret: 'secret'
    }

    post '/internal/meta/routes', payload.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer internal-token'

    expect(last_response.status).to eq(200)
    expect(WebhookRoute.where(page_id: '100').pluck(:client_key).uniq).to eq(['salute-test'])
  end

  it 'keeps rejecting a non-legacy client key for the same page' do
    WebhookRoute.create!(provider: 'meta', client_key: 'conexao', page_id: '100', target_url: 'https://salute.test/webhooks/meta', forwarding_secret: 'secret')
    payload = {
      client_key: 'salute-test',
      page_id: '100',
      target_url: 'https://salute.test/webhooks/meta',
      forwarding_secret: 'secret'
    }

    post '/internal/meta/routes', payload.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => 'Bearer internal-token'

    expect(last_response.status).to eq(409)
    expect(WebhookRoute.find_by!(page_id: '100').client_key).to eq('conexao')
  end

  it 'forwards only the matching lead to each destination with a valid signature' do
    routes = %w[100 200].map do |id|
      WebhookRoute.create!(provider: 'meta', client_key: id, page_id: id, target_url: "https://client#{id}.test/webhooks/meta", forwarding_secret: "secret#{id}")
    end
    payload = {'object' => 'page', 'entry' => routes.map { |r| {'id' => r.page_id, 'changes' => [{'field' => 'leadgen', 'value' => {'page_id' => r.page_id, 'form_id' => 'form', 'leadgen_id' => "lead#{r.page_id}"}}]} } }.to_json
    requests = routes.map do |route|
      stub_request(:post, route.target_url).with do |request|
        data = JSON.parse(request.body)
        data['entry'].size == 1 && data.dig('entry', 0, 'changes').size == 1 &&
          data.dig('entry', 0, 'changes', 0, 'value', 'page_id') == route.page_id &&
          request.headers['X-Unitymob-Gateway-Signature'] == Gateway::InternalSignature.sign(request.body, secret: route.forwarding_secret)
      end.to_return(status: 200)
    end
    post '/webhooks/meta', payload, 'CONTENT_TYPE' => 'application/json', 'HTTP_X_HUB_SIGNATURE_256' => Gateway::MetaSignature.sign(payload, app_secret: 'app-secret')
    expect(last_response.status).to eq(200)
    requests.each { |stub| expect(stub).to have_been_requested.once }
    expect(WebhookEvent.where(status: 'forwarded').count).to eq(2)
    # Legacy queued payloads also need isolation when retried.
    event = WebhookEvent.find_by!(page_id: '100')
    Gateway::EventForwarder.call(event: event, raw_body: payload)
    expect(requests.first).to have_been_requested.twice
    expect(requests.last).to have_been_requested.once
    event.update!(webhook_route: routes.last)
    Gateway::EventForwarder.call(event: event, raw_body: payload)
    expect(event.reload.status).to eq('failed')
    expect(requests.last).to have_been_requested.once
  end
end
