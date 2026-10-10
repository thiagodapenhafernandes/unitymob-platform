require_relative 'spec_helper'

RSpec.describe 'WhatsApp destination isolation' do
  include Rack::Test::Methods
  def app
    Gateway::App
  end

  it 'forwards only the matching message to each destination with a valid signature' do
    routes = %w[PHONE-A PHONE-B].map do |number|
      WebhookRoute.create!(provider: 'whatsapp', client_key: number, phone_number_id: number, waba_id: 'WABA-1', target_url: "https://#{number.downcase}.test/webhooks/whatsapp", forwarding_secret: "secret#{number}")
    end
    payload = {
      'object' => 'whatsapp_business_account',
      'entry' => routes.map do |route|
        {
          'id' => 'WABA-1',
          'changes' => [
            {
              'value' => {
                'metadata' => { 'phone_number_id' => route.phone_number_id },
                'contacts' => [{ 'wa_id' => '5511999990000', 'profile' => { 'name' => "Contact #{route.phone_number_id}" } }],
                'messages' => [{ 'id' => "wamid.#{route.phone_number_id}", 'text' => { 'body' => "secret for #{route.phone_number_id}" } }]
              }
            }
          ]
        }
      end
    }.to_json
    requests = routes.map do |route|
      stub_request(:post, route.target_url).with do |request|
        data = JSON.parse(request.body)
        data['entry'].size == 1 && data.dig('entry', 0, 'changes').size == 1 &&
          data.dig('entry', 0, 'changes', 0, 'value', 'metadata', 'phone_number_id') == route.phone_number_id &&
          data.dig('entry', 0, 'changes', 0, 'value', 'messages') == [{ 'id' => "wamid.#{route.phone_number_id}", 'text' => { 'body' => "secret for #{route.phone_number_id}" } }] &&
          request.body.scan('secret for PHONE-').size == 1 &&
          request.headers['X-Unitymob-Gateway-Signature'] == Gateway::InternalSignature.sign(request.body, secret: route.forwarding_secret)
      end.to_return(status: 200)
    end
    post '/webhooks/whatsapp', payload, 'CONTENT_TYPE' => 'application/json', 'HTTP_X_HUB_SIGNATURE_256' => Gateway::MetaSignature.sign(payload, app_secret: 'app-secret')
    expect(last_response.status).to eq(200)
    requests.each { |stub| expect(stub).to have_been_requested.once }
    expect(WebhookEvent.where(status: 'forwarded').count).to eq(2)
    routes.each do |route|
      stored = WebhookEvent.find_by!(phone_number_id: route.phone_number_id)
      expect(stored.raw_body).to include("secret for #{route.phone_number_id}")
      expect(stored.raw_body.scan('secret for PHONE-').size).to eq(1)
    end
    # Legacy queued payloads also need isolation when retried.
    event = WebhookEvent.find_by!(phone_number_id: 'PHONE-A')
    Gateway::EventForwarder.call(event: event, raw_body: payload)
    expect(requests.first).to have_been_requested.twice
    expect(requests.last).to have_been_requested.once
    event.update!(webhook_route: routes.last)
    Gateway::EventForwarder.call(event: event, raw_body: payload)
    expect(event.reload.status).to eq('failed')
    expect(requests.last).to have_been_requested.once
  end

  it 'forwards only the matching status to its own destination' do
    route = WebhookRoute.create!(provider: 'whatsapp', client_key: 'tenant-a', phone_number_id: 'PHONE-A', waba_id: 'WABA-1', target_url: 'https://tenant-a.test/webhooks/whatsapp', forwarding_secret: 'secretA')
    other = WebhookRoute.create!(provider: 'whatsapp', client_key: 'tenant-b', phone_number_id: 'PHONE-B', waba_id: 'WABA-1', target_url: 'https://tenant-b.test/webhooks/whatsapp', forwarding_secret: 'secretB')
    payload = {
      'object' => 'whatsapp_business_account',
      'entry' => [
        { 'id' => 'WABA-1', 'changes' => [{ 'value' => { 'metadata' => { 'phone_number_id' => 'PHONE-A' }, 'statuses' => [{ 'id' => 'wamid.A', 'status' => 'delivered' }] } }] },
        { 'id' => 'WABA-1', 'changes' => [{ 'value' => { 'metadata' => { 'phone_number_id' => 'PHONE-B' }, 'statuses' => [{ 'id' => 'wamid.B', 'status' => 'read' }] } }] }
      ]
    }.to_json
    stub_a = stub_request(:post, route.target_url).with do |request|
      data = JSON.parse(request.body)
      data.dig('entry', 0, 'changes', 0, 'value', 'statuses') == [{ 'id' => 'wamid.A', 'status' => 'delivered' }]
    end.to_return(status: 200)
    stub_b = stub_request(:post, other.target_url).with do |request|
      data = JSON.parse(request.body)
      data.dig('entry', 0, 'changes', 0, 'value', 'statuses') == [{ 'id' => 'wamid.B', 'status' => 'read' }]
    end.to_return(status: 200)

    post '/webhooks/whatsapp', payload, 'CONTENT_TYPE' => 'application/json', 'HTTP_X_HUB_SIGNATURE_256' => Gateway::MetaSignature.sign(payload, app_secret: 'app-secret')

    expect(last_response.status).to eq(200)
    expect(stub_a).to have_been_requested.once
    expect(stub_b).to have_been_requested.once
    expect(WebhookEvent.where(status: 'forwarded').count).to eq(2)
  end
end
