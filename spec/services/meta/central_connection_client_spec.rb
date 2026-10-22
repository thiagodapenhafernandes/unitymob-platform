require 'rails_helper'
RSpec.describe Meta::CentralConnectionClient do
  let(:user) { create(:admin_user, :admin) }
  let(:client) { described_class.new(tenant: user.tenant, user: user) }
  let(:url) { "https://webhooks.unitymob.com.br/oauth/meta/start?oauth_ticket=#{'a' * 64}" }
  around do |example|
    values = {'META_CENTRAL_CONNECT_ENABLED' => 'true', 'META_CENTRAL_CONNECT_TENANT_IDS' => user.tenant_id.to_s,
      'META_CENTRAL_CONNECT_TOKEN' => 's' * 32, 'META_CENTRAL_CONNECT_INSTANCE' => 'salute', 'FACEBOOK_APP_ID' => '1766223014200910'}
    old = ENV.to_h.slice(*values.keys)
    values.each { |k,v| ENV[k] = v }
    example.run
  ensure
    values.each_key { |k| old.key?(k) ? ENV[k] = old[k] : ENV.delete(k) }
  end
  def reply(data)
    allow(HTTParty).to receive(:post).and_return(double(success?: true, body: data.to_json))
  end
  it 'authenticates server-to-server and scopes registration to the user and tenant' do
    reply('start_url' => url)
    expect(client.register(nonce: 'n')).to eq(url)
    expect(HTTParty).to have_received(:post).with('https://webhooks.unitymob.com.br/internal/meta/oauth_attempts', hash_including(
      body: {nonce: 'n', tenant_id: user.tenant_id.to_s, user_id: user.id.to_s}.to_json,
      headers: hash_including('Authorization' => "Bearer #{'s' * 32}", 'X-Unitymob-Instance' => 'salute')))
  end
  it 'rejects open redirects and tokens in redirect URLs' do
    ['https://evil.example/oauth/meta/start', "#{url}&access_token=secret", url.sub('/oauth/meta/start', '/admin')].each do |bad|
      reply('start_url' => bad)
      expect { client.register(nonce: 'n') }.to raise_error(described_class::Error)
    end
  end
  it 'rejects a mismatched Meta app and provider cancellations' do
    reply('error' => 'authorization_declined')
    expect { client.redeem(handoff: 'h', nonce: 'n') }.to raise_error(described_class::Error)
    reply('access_token' => 't', 'facebook_user_id' => '123', 'app_id' => 'other', 'granted_permissions' => [])
    expect { client.redeem(handoff: 'h', nonce: 'n') }.to raise_error(described_class::Error)
  end
  it 'makes no request for another tenant' do
    other = double(id: user.tenant_id + 1)
    other_client = described_class.new(tenant: other, user: user)
    expect(HTTParty).not_to receive(:post)
    expect { other_client.register(nonce: 'n') }.to raise_error(described_class::Error)
  end

  it 'fails safely for malformed gateway responses' do
    [nil, {}, 'x' * 16385].each do |body|
      allow(HTTParty).to receive(:post).and_return(double(success?: true, body: body))
      expect { client.register(nonce: 'n') }.to raise_error(described_class::Error)
    end
    reply('start_url' => {})
    expect { client.register(nonce: 'n') }.to raise_error(described_class::Error)
  end
end
