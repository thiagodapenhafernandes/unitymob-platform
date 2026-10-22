require 'rails_helper'

RSpec.describe 'Authenticated gateway webhook limits' do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    keys = %w[AUTHENTICATED_GATEWAY_WEBHOOK_LIMIT WHATSAPP_WEBHOOK_GATEWAY_FORWARDING_SECRET]
    old = ENV.to_h.slice(*keys)
    old_store = Rack::Attack.cache.store
    old_enabled = Rack::Attack.enabled
    ENV['AUTHENTICATED_GATEWAY_WEBHOOK_LIMIT'] = '400'
    ENV['WHATSAPP_WEBHOOK_GATEWAY_FORWARDING_SECRET'] = 'test-forward-secret'
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.enabled = true
    travel_to(Time.zone.local(2026, 10, 22, 12)) { example.run }
  ensure
    keys.each { |key| old.key?(key) ? ENV[key] = old[key] : ENV.delete(key) }
    Rack::Attack.reset!
    Rack::Attack.cache.store = old_store
    Rack::Attack.enabled = old_enabled
  end

  let(:body) { '{"object":"page"}' }
  let(:signature) { 'sha256=' + OpenSSL::HMAC.hexdigest('SHA256', 'test-forward-secret', body) }
  let(:endpoint) { ->(env) { [200, {}, [env['rack.input'].read]] } }

  def send_request(path = '/webhooks/meta', signature: self.signature, payload: body)
    env = Rack::MockRequest.env_for(path, method: 'POST', input: payload)
    env['REMOTE_ADDR'] = '159.223.105.26'
    env['HTTP_X_UNITYMOB_GATEWAY_SIGNATURE'] = signature if signature
    Rack::Attack.new(endpoint).call(env)
  end

  it 'accepts signed delivery beyond the public quota and preserves the exact body' do
    301.times { expect(send_request).to eq([200, {}, [body]]) }
  end

  it 'still bounds signed traffic and keeps Meta and WhatsApp quotas independent' do
    400.times { send_request }
    expect(send_request.first).to eq(429)
    expect(send_request('/webhooks/whatsapp').first).to eq(200)
  end

  it 'does not trust a forged signature, absent signature or tampered body' do
    300.times { send_request(signature: 'sha256=' + '0' * 64) }
    expect(send_request(signature: nil).first).to eq(429)
    expect(send_request(payload: body + ' ').first).to eq(429)
    expect(send_request.first).to eq(200)
  end

  it 'retains the original shared public limit when the opt-in is absent' do
    ENV.delete('AUTHENTICATED_GATEWAY_WEBHOOK_LIMIT')
    300.times { send_request }
    expect(send_request('/webhooks/whatsapp').first).to eq(429)
  end

  it 'fails closed without a forwarding secret' do
    ENV.delete('WHATSAPP_WEBHOOK_GATEWAY_FORWARDING_SECRET')
    300.times { send_request }
    expect(send_request.first).to eq(429)
  end
end
