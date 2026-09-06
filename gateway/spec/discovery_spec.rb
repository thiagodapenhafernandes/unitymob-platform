require 'spec_helper'
RSpec.describe 'Discovery V2' do
  def app = Gateway::App
  def body = JSON.parse(last_response.body)
  def post_json(path, payload, headers = {})
    post path, payload.to_json, {'CONTENT_TYPE' => 'application/json'}.merge(headers)
  end
  def register(instance = 'salute', tenant = '1', email = 'broker@example.com', active = true, time = Time.now.utc)
    post_json '/internal/discovery/v2/memberships', {tenant_id: tenant, user_id: '9', email: email, tenant_name: instance,
      active: active, source_updated_at: time.iso8601(6)}, {'HTTP_X_UNITYMOB_INSTANCE' => instance, 'HTTP_AUTHORIZATION' => "Bearer #{instance == 'salute' ? 's' * 32 : 'c' * 32}"}
  end
  before do
    ENV['DISCOVERY_SECRET'] = 'x' * 40
    ENV['DISCOVERY_INSTANCES'] = {salute: {token: 's' * 32, origin: 'https://saluteimoveis.com.br', tenant_ids: ['1']},
      conexao: {token: 'c' * 32, origin: 'https://conexaobc.com', tenant_ids: ['72']}}.to_json
    allow(Gateway::Discovery).to receive(:send_code) { |_, code| @code = code }
  end
  after { ENV.delete('DISCOVERY_SECRET'); ENV.delete('DISCOVERY_INSTANCES') }
  it 'keeps both memberships, scopes deactivation and rejects stale updates' do
    register
    register('conexao', '72')
    expect(AccountMembership.count).to eq(2)
    register('salute', '72')
    expect(last_response.status).to eq(403)
    register('salute', '1', 'broker@example.com', false)
    expect(AccountMembership.where(active: true).pluck(:instance_id)).to eq(['conexao'])
    register('salute', '1', 'broker@example.com', true, Time.now.utc - 60)
    expect(AccountMembership.find_by(instance_id: 'salute').active).to eq(false)
  end
  it 'rejects shared legacy tokens and validates destinations' do
    post_json '/internal/discovery/v2/memberships', {}, {'HTTP_X_UNITYMOB_INSTANCE' => 'salute', 'HTTP_AUTHORIZATION' => 'Bearer internal-token'}
    expect(last_response.status).to eq(401)
    register
    expect(AccountMembership.first.public_account[:origin]).to eq('https://saluteimoveis.com.br')
    expect { Gateway::Discovery.origin('https://example.com@evil.com/path') }.to raise_error(ArgumentError)
  end
  it 'reveals both accounts only after verification and consumes the code' do
    register
    register('conexao', '72')
    post_json '/discovery/v2/challenges', {email: 'Broker@example.com'}
    expect(last_response.status).to eq(202)
    token = body.fetch('challenge')
    expect(last_response.body).not_to include('salute', 'conexao')
    post_json '/discovery/v2/verify', {challenge: token, code: @code}
    expect(body.fetch('accounts').map { |a| a['instance_id'] }).to eq(%w[conexao salute])
    post_json '/discovery/v2/verify', {challenge: token, code: @code}
    expect(last_response.status).to eq(422)
  end
  it 'sends the same challenge for an unknown email and returns no accounts after verification' do
    post_json '/discovery/v2/challenges', {email: 'unknown@example.com'}
    expect(last_response.status).to eq(202)
    post_json '/discovery/v2/verify', {challenge: body.fetch('challenge'), code: @code}
    expect(body.fetch('accounts')).to eq([])
  end
  it 'limits code attempts and repeated sends' do
    post_json '/discovery/v2/challenges', {email: 'broker@example.com'}
    token = body.fetch('challenge')
    5.times { post_json '/discovery/v2/verify', {challenge: token, code: 'wrong'} }
    post_json '/discovery/v2/verify', {challenge: token, code: @code}
    expect(last_response.status).to eq(422)
    3.times { post_json '/discovery/v2/challenges', {email: 'broker@example.com'} }
    expect(last_response.status).to eq(429)
    expect(DiscoveryChallenge.first.attempts).to eq(5)
  end
  it 'does not reuse an expired challenge and cleans it without affecting memberships' do
    register
    post_json '/discovery/v2/challenges', {email: 'broker@example.com'}
    token = body.fetch('challenge')
    DiscoveryChallenge.update_all(expires_at: Time.now.utc - 1)
    post_json '/discovery/v2/verify', {challenge: token, code: @code}
    expect(last_response.status).to eq(422)
    expect(AccountMembership.count).to eq(1)
  end
  it 'updates email on the same identity and retains the other instance membership' do
    register
    register('conexao', '72')
    register('salute', '1', 'new@example.com')
    expect(AccountMembership.where(email: 'broker@example.com').pluck(:instance_id)).to eq(['conexao'])
    expect(AccountMembership.count).to eq(2)
  end
  it 'keeps the legacy success contract for a single account and rejects ambiguous routing' do
    register
    post_json '/discovery/resolve', {email: 'broker@example.com'}
    expect(body).to eq('tenant_url' => 'https://saluteimoveis.com.br')
    register('conexao', '72')
    post_json '/discovery/resolve', {email: 'broker@example.com'}
    expect(last_response.status).to eq(409)
    expect(body.fetch('error')).to eq('multiple_accounts')
  end
  it 'rejects non-object payloads and oversized bodies' do
    post_json '/discovery/v2/challenges', []
    expect(last_response.status).to eq(422)
    post_json '/discovery/v2/challenges', {email: 'x' * 5000}
    expect(last_response.status).to eq(413)
  end

end
