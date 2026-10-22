require 'spec_helper'

RSpec.describe 'Central Meta connection' do
  def app = Gateway::App
  def post_json(path, data, token: 's' * 32)
    post path, data.to_json, {'CONTENT_TYPE' => 'application/json', 'HTTP_X_UNITYMOB_INSTANCE' => 'salute', 'HTTP_AUTHORIZATION' => "Bearer #{token}"}
  end
  let(:context) { {tenant_id: '1', user_id: '9', nonce: 'a' * 64} }
  let(:identity) { {'access_token' => 'private-token', 'facebook_user_id' => '123', 'granted_permissions' => Gateway::MetaOauth::SCOPES, 'app_id' => '1766223014200910'} }
  around do |example|
    values = {'DISCOVERY_SECRET' => 'd' * 40, 'META_OAUTH_ENABLED' => 'true', 'META_OAUTH_APP_ID' => '1766223014200910',
      'META_OAUTH_ENCRYPTION_KEY' => 'b' * 64, 'META_OAUTH_PUBLIC_ORIGIN' => 'https://webhooks.unitymob.com.br',
      'META_OAUTH_INSTANCES' => {salute: {enabled: true, token: 's' * 32, origin: 'https://saluteimoveis.com.br', tenant_ids: ['1']}}.to_json}
    old = ENV.to_h.slice(*values.keys)
    values.each { |k,v| ENV[k] = v }
    example.run
  ensure
    values.each_key { |k| old.key?(k) ? ENV[k] = old[k] : ENV.delete(k) }
  end
  def start_flow
    post_json '/internal/meta/oauth_attempts', context
    expect(last_response.status).to eq(200)
    start = URI(JSON.parse(last_response.body).fetch('start_url'))
    @start_path = "#{start.path}?#{start.query}"
    get @start_path
    expect(last_response.status).to eq(302)
    URI.decode_www_form(URI(last_response.location).query).to_h.fetch('state')
  end
  def finish_flow(state, **params)
    get '/oauth/meta/callback', {state: state, code: 'authorization-code'}.merge(params)
    expect(last_response.status).to eq(302)
    uri = URI(last_response.location)
    expect(uri.host).to eq('saluteimoveis.com.br')
    expect(uri.query).not_to include('private-token', 'authorization-code')
    URI.decode_www_form(uri.query).to_h.fetch('oauth_handoff')
  end
  before { allow(Gateway::MetaOauth).to receive(:exchange).with('authorization-code').and_return(identity) }

  it 'encrypts credentials, binds the tenant and consumes the handoff once' do
    state = start_flow
    handoff = finish_flow(state)
    get @start_path
    expect(last_response.status).to eq(410)
    attempt = MetaOauthAttempt.first
    expect(attempt.encrypted_result).not_to include('private-token')
    expect(attempt.nonce_digest).not_to eq(context.fetch(:nonce))
    post_json '/internal/meta/oauth_attempts/redeem', context.merge(handoff: handoff, tenant_id: '72')
    expect(last_response.status).to eq(403)
    post_json '/internal/meta/oauth_attempts/redeem', context.merge(handoff: handoff)
    expect(last_response.status).to eq(200)
    expect(JSON.parse(last_response.body)).to eq(identity)
    expect(attempt.reload.encrypted_result).to be_nil
    post_json '/internal/meta/oauth_attempts/redeem', context.merge(handoff: handoff)
    expect(last_response.status).to eq(410)
    get '/oauth/meta/callback', state: state, code: 'authorization-code'
    expect(last_response.status).to eq(410)
  end
  it 'rejects other browser sessions and invalid states' do
    state = start_flow
    clear_cookies
    get '/oauth/meta/callback', state: state, code: 'authorization-code'
    expect(last_response.status).to eq(400)
    expect(Gateway::MetaOauth).not_to have_received(:exchange)
  end
  it 'returns cancellation without exchanging a token' do
    state = start_flow
    handoff = finish_flow(state, error: 'access_denied')
    post_json '/internal/meta/oauth_attempts/redeem', context.merge(handoff: handoff)
    expect(JSON.parse(last_response.body)).to eq('error' => 'authorization_declined')
    expect(Gateway::MetaOauth).not_to have_received(:exchange)
  end
  it 'rejects expired attempts, credentials and tenants' do
    post_json '/internal/meta/oauth_attempts', context, token: 'wrong'
    expect(last_response.status).to eq(401)
    post_json '/internal/meta/oauth_attempts', context.merge(tenant_id: '72')
    expect(last_response.status).to eq(403)
    state = start_flow
    MetaOauthAttempt.update_all(expires_at: Time.now - 1)
    get '/oauth/meta/callback', state: state, code: 'authorization-code'
    expect(last_response.status).to eq(410)
  end
  it 'stays disabled by default without affecting health' do
    ENV.delete('META_OAUTH_ENABLED')
    post_json '/internal/meta/oauth_attempts', context
    expect(last_response.status).to eq(404)
    get '/up'
    expect(last_response.status).to eq(200)
  end
  it 'fails safely on provider errors' do
    state = start_flow
    allow(Gateway::MetaOauth).to receive(:exchange).and_raise(Gateway::MetaOauth::Unavailable)
    get '/oauth/meta/callback', state: state, code: 'authorization-code'
    expect(last_response.status).to eq(502)
    expect(MetaOauthAttempt.first.encrypted_result).to be_nil
    expect(last_response.headers['Cache-Control']).to eq('no-store')
  end
  it 'rejects ticket replay, wrong user, wrong nonce and limits registrations' do
    state = start_flow
    handoff = finish_flow(state)
    [context.merge(user_id: '10'), context.merge(nonce: 'b' * 64)].each do |wrong|
      post_json '/internal/meta/oauth_attempts/redeem', wrong.merge(handoff: handoff)
      expect(last_response.status).to eq(403)
    end
    9.times { post_json '/internal/meta/oauth_attempts', context }
    expect(last_response.status).to eq(200)
    post_json '/internal/meta/oauth_attempts', context
    expect(last_response.status).to eq(429)
  end
  it 'requires Ads permissions from the provider and accepts complete results' do
    allow(Gateway::MetaOauth).to receive(:exchange).and_call_original
    allow(Gateway::MetaOauth).to receive(:graph).with('oauth/access_token', anything).and_return('access_token' => 'new')
    allow(Gateway::MetaOauth).to receive(:graph).with('me', anything).and_return('id' => '123')
    allow(Gateway::MetaOauth).to receive(:graph).with('me/permissions', anything).and_return('data' => [])
    expect { Gateway::MetaOauth.exchange('code') }.to raise_error(Gateway::MetaOauth::Unavailable)
    permissions = Gateway::MetaOauth::SCOPES.map { |scope| {'permission' => scope, 'status' => 'granted'} }
    allow(Gateway::MetaOauth).to receive(:graph).with('me/permissions', anything).and_return('data' => permissions)
    expect(Gateway::MetaOauth.exchange('code')).to include('access_token' => 'new', 'facebook_user_id' => '123')
  end

  it 'rejects instance revocation without changing legacy routes' do
    state = start_flow
    ENV['META_OAUTH_INSTANCES'] = '{}'
    get '/oauth/meta/callback', state: state, code: 'authorization-code'
    expect(last_response.status).to eq(502)
    expect(Gateway::MetaOauth).not_to have_received(:exchange)
    get '/up'
    expect(last_response.status).to eq(200)
  end

  it 'limits request bodies and rejects plaintext nonce storage' do
    post_json '/internal/meta/oauth_attempts', context.merge(extra: 'x' * 4096)
    expect(last_response.status).to eq(413)
    expect(MetaOauthAttempt.count).to eq(0)
  end

  it 'consumes a handoff at most once under concurrent requests' do
    state = start_flow
    handoff = finish_flow(state)
    requests = Array.new(2) do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Rack::MockRequest.new(app).post('/internal/meta/oauth_attempts/redeem',
            'CONTENT_TYPE' => 'application/json', 'HTTP_X_UNITYMOB_INSTANCE' => 'salute',
            'HTTP_AUTHORIZATION' => "Bearer #{'s' * 32}", input: context.merge(handoff: handoff).to_json).status
        end
      end
    end
    expect(requests.map(&:value).sort).to eq([200, 410])
    expect(MetaOauthAttempt.first.encrypted_result).to be_nil
  end

  it 'refuses an expired handoff without returning credentials' do
    handoff = finish_flow(start_flow)
    MetaOauthAttempt.update_all(expires_at: Time.now - 1)
    post_json '/internal/meta/oauth_attempts/redeem', context.merge(handoff: handoff)
    expect(last_response.status).to eq(410)
    expect(last_response.body).not_to include('private-token')
    expect(MetaOauthAttempt.first.consumed_at).to be_nil
  end

  it 'refuses corrupted encrypted credentials without consuming the handoff' do
    handoff = finish_flow(start_flow)
    MetaOauthAttempt.first.update!(encrypted_result: 'corrupted')
    post_json '/internal/meta/oauth_attempts/redeem', context.merge(handoff: handoff)
    expect(last_response.status).to eq(410)
    expect(last_response.body).not_to include('private-token')
    expect(MetaOauthAttempt.first.consumed_at).to be_nil
  end

  it 'rejects credentials from another configured instance' do
    handoff = finish_flow(start_flow)
    instances = JSON.parse(ENV.fetch('META_OAUTH_INSTANCES'))
    instances['other'] = instances.fetch('salute').merge('token' => 'o' * 32)
    ENV['META_OAUTH_INSTANCES'] = instances.to_json
    post '/internal/meta/oauth_attempts/redeem', context.merge(handoff: handoff).to_json,
      {'CONTENT_TYPE' => 'application/json', 'HTTP_X_UNITYMOB_INSTANCE' => 'other', 'HTTP_AUTHORIZATION' => "Bearer #{'o' * 32}"}
    expect(last_response.status).to eq(403)
    expect(MetaOauthAttempt.first.consumed_at).to be_nil
  end

end
