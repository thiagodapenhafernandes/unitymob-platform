require 'spec_helper'

RSpec.describe 'Queued Meta and WhatsApp delivery' do
  def app; Gateway::App; end

  around do |example|
    previous = ENV['GATEWAY_ASYNC_DELIVERY_ENABLED']
    ENV['GATEWAY_ASYNC_DELIVERY_ENABLED'] = 'true'
    example.run
  ensure
    ENV['GATEWAY_ASYNC_DELIVERY_ENABLED'] = previous
  end

  let!(:route) { WebhookRoute.create!(provider: 'meta', client_key: 'salute', page_id: '100', target_url: 'https://salute.test/webhooks/meta', forwarding_secret: 'secret') }

  def meta_payload(id = 'lead1', page = '100')
    { 'object' => 'page', 'entry' => [{ 'id' => page, 'changes' => [{ 'field' => 'leadgen', 'value' => { 'page_id' => page, 'form_id' => 'form', 'leadgen_id' => id } }] }] }
  end

  def receive_meta(id = 'lead1', page = '100')
    body = meta_payload(id, page).to_json
    post '/webhooks/meta', body, 'CONTENT_TYPE' => 'application/json',
      'HTTP_X_HUB_SIGNATURE_256' => Gateway::MetaSignature.sign(body, app_secret: 'app-secret')
    expect(last_response.status).to eq(200)
    WebhookEvent.order(:id).last
  end

  it 'persists before responding, without forwarding, and consumes a repeated receipt once' do
    delivery = stub_request(:post, route.target_url).to_return(status: 200)
    event = receive_meta
    3.times { receive_meta }
    expect(WebhookEvent.count).to eq(1)
    expect(event).to have_attributes(status: 'received', attempts: 0)
    expect(delivery).not_to have_been_requested
    expect(Gateway::DeliveryWorker.tick).to eq(1)
    expect(event.reload).to have_attributes(status: 'forwarded', attempts: 1)
    receive_meta
    Gateway::DeliveryWorker.tick
    expect(delivery).to have_been_requested.once
  end

  it 'does not enqueue historical receipts, including failed copies' do
    old = WebhookEvent.create!(provider: 'meta', webhook_route: route, page_id: '100', form_id: 'form', external_id: 'lead1', event_type: 'leadgen',
      payload: meta_payload, raw_body: meta_payload.to_json, status: 'failed', attempts: 1, received_at: Time.now - 86400)
    # Use the extractor's actual event type, also used by historical receipts.
    old.update!(event_type: Gateway::MetaLeadPayload.extract_event_contexts(meta_payload).first[:event_type])
    receive_meta
    expect(WebhookEvent.count).to eq(1)
    expect(old.reload.queued_at).to be_nil
    expect(Gateway::DeliveryWorker.tick).to eq(0)
  end

  it 'does not consume unsigned requests' do
    post '/webhooks/meta', meta_payload.to_json, 'CONTENT_TYPE' => 'application/json'
    expect(last_response.status).to eq(401)
    expect(WebhookEvent.count).to eq(0)
  end

  it 'does not acknowledge a receipt that could not be stored' do
    allow(Gateway::QueuedDelivery).to receive(:persist).and_raise(ActiveRecord::ConnectionNotEstablished)
    raw = meta_payload.to_json
    post '/webhooks/meta', raw, 'CONTENT_TYPE' => 'application/json',
      'HTTP_X_HUB_SIGNATURE_256' => Gateway::MetaSignature.sign(raw, app_secret: 'app-secret')
    expect(last_response.status).to eq(500)
    expect(WebhookEvent.count).to eq(0)
  end

  it 'leaves historical records out of the worker and queued records out of legacy retries' do
    old = WebhookEvent.create!(provider: 'meta', webhook_route: route, event_type: 'leadgen', status: 'failed', received_at: Time.now - 60)
    queued = receive_meta
    queued.update!(status: 'failed', next_retry_at: Time.now - 1)
    allow(Gateway::EventForwarder).to receive(:call)
    Gateway::DeliveryWorker.tick
    expect(Gateway::EventForwarder).not_to have_received(:call).with(event: old, raw_body: anything)
    expect(old.reload.attempts).to eq(0)
    Gateway::RetryFailedEvents.call
    expect(Gateway::EventForwarder).to have_received(:call).with(event: queued, raw_body: anything).once
    expect(Gateway::EventForwarder).to have_received(:call).with(event: old, raw_body: anything).once
  end

  it 'pauses all deliveries to a host on 429 but continues another host' do
    WebhookRoute.create!(provider: 'meta', client_key: 'other', page_id: '200', target_url: 'https://other.test/webhooks/meta', forwarding_secret: 'other')
    rejected = stub_request(:post, route.target_url).to_return(status: 429, headers: { 'Retry-After' => '60' })
    other = stub_request(:post, 'https://other.test/webhooks/meta').to_return(status: 200)
    first = receive_meta
    second = receive_meta('lead2')
    wa = WebhookRoute.create!(client_key: 'salute', phone_number_id: 'phone', target_url: 'https://salute.test/webhooks/whatsapp', forwarding_secret: 'secret')
    wa_event = Gateway::QueuedDelivery.persist(provider: 'whatsapp', webhook_route: wa, external_id: 'wamid1', event_type: 'message',
      phone_number_id: 'phone', payload: { 'entry' => [] }, raw_body: '{}', status: 'received', received_at: Time.now)
    receive_meta('other', '200')
    before = Time.now
    expect(Gateway::DeliveryWorker.tick).to eq(2)
    expect(first.reload.next_retry_at).to be >= before + 60
    Gateway::DeliveryWorker.tick
    expect(second.reload.attempts).to eq(0)
    expect(wa_event.reload.attempts).to eq(0)
    expect(rejected).to have_been_requested.once
    expect(other).to have_been_requested.once
  end

  it 'shares the delivery budget between provider routes on the same host' do
    receive_meta
    receive_meta('lead2')
    delivery = stub_request(:post, route.target_url).to_return(status: 200)
    Gateway::DeliveryWorker.tick
    Gateway::DeliveryWorker.tick
    expect(delivery).to have_been_requested.once
    DeliveryDestination.update_all(available_at: Time.now - 1)
    Gateway::DeliveryWorker.tick
    expect(delivery).to have_been_requested.twice
  end

  it 'refuses to follow a changed destination without touching another tenant' do
    event = receive_meta
    route.update!(target_url: 'https://another.test/webhooks/meta')
    Gateway::DeliveryWorker.tick
    expect(event.reload).to have_attributes(status: 'failed', attempts: 0)
    expect(event.queue_finished_at).to be_present
    expect(WebMock).not_to have_requested(:post, 'https://another.test/webhooks/meta')
  end

  it 'does not let an in-progress worker deliver the same host concurrently' do
    event = receive_meta
    WebhookRoute.create!(provider: 'meta', client_key: 'other', page_id: '200', target_url: 'https://other.test/webhooks/meta', forwarding_secret: 'other')
    other = receive_meta('other', '200')
    stub_request(:post, 'https://other.test/webhooks/meta').to_return(status: 200)
    entered = Queue.new
    release = Queue.new
    delivery = stub_request(:post, route.target_url).to_return do
      entered << true
      release.pop
      { status: 200 }
    end
    thread = Thread.new { ActiveRecord::Base.connection_pool.with_connection { Gateway::DeliveryWorker.tick } }
    Timeout.timeout(5) { entered.pop }
    # New receipts must not wait for a slow network delivery's destination lock.
    attributes = { provider: 'meta', webhook_route: route, page_id: '100', form_id: 'form', external_id: 'new-during-delivery',
      event_type: 'leadgen', payload: meta_payload('new-during-delivery'), raw_body: meta_payload('new-during-delivery').to_json,
      status: 'received', received_at: Time.now }
    inserted = Thread.new { ActiveRecord::Base.connection_pool.with_connection { Gateway::QueuedDelivery.persist(attributes) } }
    Timeout.timeout(5) { inserted.value }
    expect(Gateway::DeliveryWorker.tick).to eq(1)
    expect(other.reload.status).to eq('forwarded')
    release << true
    thread.value
    expect(event.reload.attempts).to eq(1)
    expect(delivery).to have_been_requested.once
  ensure
    release << true if release
    thread&.join(5)
    inserted&.join(5)
  end

  it 'accepts a legitimate burst beyond the CRM public quota without inline forwarding' do
    delivery = stub_request(:post, route.target_url).to_return(status: 200)
    320.times { |index| receive_meta("burst#{index}") }
    expect(WebhookEvent.where(status: 'received', attempts: 0).count).to eq(320)
    expect(delivery).not_to have_been_requested
    Gateway::DeliveryWorker.tick
    Gateway::DeliveryWorker.tick
    expect(delivery).to have_been_requested.once
  end

  it 'retries only new failed deliveries when due, without blocking other ready receipts' do
    first = receive_meta
    second = receive_meta('lead2')
    delivery = stub_request(:post, route.target_url).to_return(status: 503).then.to_return(status: 200)
    Gateway::DeliveryWorker.tick
    expect(first.reload).to have_attributes(status: 'failed', attempts: 1)
    DeliveryDestination.update_all(available_at: Time.now - 1)
    Gateway::DeliveryWorker.tick
    expect(second.reload.status).to eq('forwarded')
    expect(first.reload.attempts).to eq(1)
    first.update!(next_retry_at: Time.now - 1)
    DeliveryDestination.update_all(available_at: Time.now - 1)
    Gateway::DeliveryWorker.tick
    expect(first.reload).to have_attributes(status: 'forwarded', attempts: 2)
    expect(delivery).to have_been_requested.times(3)
  end

  it 'keeps receipt identity unique under concurrent provider redelivery' do
    attributes = { provider: 'meta', webhook_route: route, page_id: '100', form_id: 'form', external_id: 'lead1',
      event_type: 'leadgen', payload: meta_payload, raw_body: meta_payload.to_json, status: 'received', received_at: Time.now }
    threads = Array.new(3) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { Gateway::QueuedDelivery.persist(attributes).id }
      end
    end
    expect(threads.map(&:value).uniq.size).to eq(1)
    expect(WebhookEvent.count).to eq(1)
    expect(DeliveryDestination.count).to eq(1)
  end

  it 'retains a persisted receipt for a later worker invocation' do
    event = receive_meta
    expect(event.queue_finished_at).to be_nil
    stub_request(:post, route.target_url).to_return(status: 200)
    Gateway::DeliveryWorker.tick
    expect(event.reload.queue_finished_at).to be_present
  end

  it 'alerts unrouted events outside the HTTP request and only once' do
    allow(Gateway::UnroutedEventAlerter).to receive(:call)
    receive_meta('unknown', '900')
    expect(Gateway::UnroutedEventAlerter).not_to have_received(:call)
    Gateway::DeliveryWorker.tick
    DeliveryDestination.update_all(available_at: Time.now - 1)
    Gateway::DeliveryWorker.tick
    expect(Gateway::UnroutedEventAlerter).to have_received(:call).once
  end

  it 'keeps distinct WhatsApp status transitions while ignoring envelope retries' do
    wa = WebhookRoute.create!(client_key: 'salute', phone_number_id: 'phone', target_url: 'https://salute.test/webhooks/whatsapp', forwarding_secret: 'secret')
    body = { 'object' => 'whatsapp_business_account', 'entry' => [{ 'id' => 'waba', 'time' => 1, 'changes' => [{ 'value' => {
      'metadata' => { 'phone_number_id' => 'phone' }, 'statuses' => [{ 'id' => 'wamid1', 'status' => 'sent', 'timestamp' => '1' }]
    } }] }] }
    %w[sent delivered read].each do |status|
      body['entry'][0]['changes'][0]['value']['statuses'][0]['status'] = status
      2.times do |time|
        body['entry'][0]['time'] = time
        raw = body.to_json
        post '/webhooks/whatsapp', raw, 'CONTENT_TYPE' => 'application/json', 'HTTP_X_HUB_SIGNATURE_256' => Gateway::MetaSignature.sign(raw, app_secret: 'app-secret')
        expect(last_response.status).to eq(200)
      end
    end
    expect(WebhookEvent.where(webhook_route: wa).count).to eq(3)
    expect(DeliveryDestination.count).to eq(1)
  end
end
