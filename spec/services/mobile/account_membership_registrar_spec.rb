require 'rails_helper'
RSpec.describe Mobile::AccountMembershipRegistrar do
  around do |example|
    keys = %w[DISCOVERY_INSTANCE_ID DISCOVERY_INSTANCE_TOKEN DISCOVERY_GATEWAY_URL]
    old = ENV.slice(*keys)
    ENV['DISCOVERY_INSTANCE_ID'] = 'test'
    ENV['DISCOVERY_INSTANCE_TOKEN'] = 's' * 32
    ENV['DISCOVERY_GATEWAY_URL'] = 'https://gateway.example.com'
    example.run
  ensure
    keys.each { |key| old.key?(key) ? ENV[key] = old[key] : ENV.delete(key) }
  end
  it 'publishes a stable account identity and active state without accepting a target URL' do
    user = create(:admin_user)
    stubs = Faraday::Adapter::Test::Stubs.new do |stub|
      stub.post('/internal/discovery/v2/memberships') do |request|
        data = JSON.parse(request.body)
        expect(data).to include('tenant_id' => user.tenant_id.to_s, 'user_id' => user.id.to_s, 'active' => false)
        expect(data).not_to have_key('target_url')
        expect(request.request_headers['Authorization']).to eq("Bearer #{'s' * 32}")
        [200, {}, '{}']
      end
    end
    connection = Faraday.new { |builder| builder.adapter(:test, stubs) }
    allow(Faraday).to receive(:new).and_return(connection)
    user.update!(active: false)
    described_class.sync!(user)
    stubs.verify_stubbed_calls
  end
  it 'enqueues updates on activation changes and a tombstone on deletion' do
    user = create(:admin_user)
    expect { user.update!(active: false) }.to have_enqueued_job(Mobile::SyncAccountMembershipJob).with(user.id)
    expect { user.destroy! }.to have_enqueued_job(Mobile::SyncAccountMembershipJob).with(user.id, hash_including(active: false, tenant_id: user.tenant_id.to_s))
  end
  it 'retries transport errors without logging credentials or email' do
    user = create(:admin_user)
    stubs = Faraday::Adapter::Test::Stubs.new { |stub| stub.post('/internal/discovery/v2/memberships') { [503, {}, ''] } }
    connection = Faraday.new { |builder| builder.adapter(:test, stubs) }
    allow(Faraday).to receive(:new).and_return(connection)
    expect { described_class.sync!(user) }.to raise_error(Faraday::Error, 'Discovery synchronization failed (503)')
  end
  it 'uses the primary email for a mirror and enqueues its removal when the primary is deleted' do
    primary = create(:admin_user)
    other = Tenant.create!(name: "Mirror", slug: "mirror-#{SecureRandom.hex(4)}")
    mirror = create(:admin_user, tenant: other, primary_admin_user: primary)
    allow(described_class).to receive(:publish!)
    described_class.sync!(mirror)
    expect(described_class).to have_received(:publish!).with(hash_including(email: primary.email, user_id: mirror.id.to_s, active: false))
    expect { primary.destroy! }.to have_enqueued_job(Mobile::SyncAccountMembershipJob).with(mirror.id, hash_including(active: false, tenant_id: other.id.to_s))
  end

end
