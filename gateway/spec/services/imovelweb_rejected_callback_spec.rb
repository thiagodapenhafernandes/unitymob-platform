require 'spec_helper'

RSpec.describe Gateway::ImovelwebRejectedCallback do
  around do |example|
    previous = ENV['IMOVELWEB_SANDBOX_CALLBACK_TOKEN']
    ENV['IMOVELWEB_SANDBOX_CALLBACK_TOKEN'] = 't' * 32
    example.run
  ensure
    previous ? ENV['IMOVELWEB_SANDBOX_CALLBACK_TOKEN'] = previous : ENV.delete('IMOVELWEB_SANDBOX_CALLBACK_TOKEN')
  end

  it 'retains authenticated rejected bodies encrypted, once, outside every delivery queue' do
    raw = '{"email":"private@example.com","phone":"private-phone"}'
    2.times { described_class.record(environment: 'sandbox', raw: raw, reason: 'phone:scalar_required') }
    expect(WebhookEvent.count).to eq(1)
    event = WebhookEvent.last
    expect(event.attributes.to_json).not_to include('private@example.com', 'private-phone')
    expect(described_class.cipher('sandbox').decrypt_and_verify(event.payload.fetch('encrypted_body'))).to eq(raw)
    expect(event.webhook_route_id).to be_nil
    expect(event.queued_at).to be_nil
    expect(Gateway::DeliveryWorker.tick).to eq(0)
    expect(Gateway::RetryFailedEvents.call.retried).to eq(0)
  end
end
