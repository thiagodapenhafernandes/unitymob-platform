require 'rails_helper'
RSpec.describe 'Central Meta pilot', type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers
  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }
  let(:client) { instance_double(Meta::CentralConnectionClient, origin: 'https://localhost') }
  let(:start_url) { "https://webhooks.unitymob.com.br/oauth/meta/start?oauth_ticket=#{'b' * 64}" }
  around do |example|
    keys = %w[META_CENTRAL_CONNECT_ENABLED META_CENTRAL_CONNECT_TENANT_IDS]
    old = ENV.to_h.slice(*keys)
    ENV['META_CENTRAL_CONNECT_ENABLED'] = 'true'
    ENV['META_CENTRAL_CONNECT_TENANT_IDS'] = tenant.id.to_s
    example.run
  ensure
    keys.each { |key| old.key?(key) ? ENV[key] = old[key] : ENV.delete(key) }
  end
  before do
    host! 'localhost'
    https!
    sign_in admin
    allow(Meta::CentralConnectionClient).to receive(:new).and_return(client)
    allow(client).to receive(:register).and_return(start_url)
  end
  it 'registers for an authenticated pilot user and completes only once' do
    post admin_meta_connection_path
    expect(response).to redirect_to(start_url)
    expect(client).to have_received(:register).with(nonce: match(/\A[0-9a-f]{64}\z/))
    allow(client).to receive(:redeem).and_return({'access_token' => 'test'})
    allow(Meta::ConnectionCompletion).to receive(:call)
    get admin_meta_connection_path, params: {oauth_handoff: 'c' * 64}
    expect(response).to redirect_to(admin_meta_integrations_path)
    expect(Meta::ConnectionCompletion).to have_received(:call).with(integration: have_attributes(tenant_id: tenant.id, admin_user_id: admin.id), identity: {'access_token' => 'test'}, preserve_permissions: true)
    get admin_meta_connection_path, params: {oauth_handoff: 'c' * 64}
    expect(client).to have_received(:redeem).once
  end
  it 'rejects unsolicited callbacks' do
    expect(client).not_to receive(:redeem)
    get admin_meta_connection_path, params: {oauth_handoff: 'c' * 64}
    expect(response).to redirect_to(admin_meta_integrations_path)
  end
  it 'returns 404 with the feature disabled or outside the allowlist' do
    ENV['META_CENTRAL_CONNECT_ENABLED'] = 'false'
    post admin_meta_connection_path
    expect(response).to have_http_status(:not_found)
    ENV['META_CENTRAL_CONNECT_ENABLED'] = 'true'
    ENV['META_CENTRAL_CONNECT_TENANT_IDS'] = (tenant.id + 1).to_s
    post admin_meta_connection_path
    expect(response).to have_http_status(:not_found)
    expect(client).not_to have_received(:register)
  end
  it 'rejects an alternate origin' do
    allow(client).to receive(:origin).and_return('https://other.example')
    post admin_meta_connection_path
    expect(response).to have_http_status(:not_found)
  end
  it 'requires authentication' do
    sign_out admin
    post admin_meta_connection_path
    expect(response).to redirect_to(new_admin_user_session_path)
  end
  it 'rejects users without integration management permission' do
    sign_out admin
    restricted = create(:admin_user)
    sign_in restricted
    allow_any_instance_of(AdminUser).to receive(:can?).with(:manage, :integracoes).and_return(false)
    post admin_meta_connection_path
    expect(client).not_to have_received(:register)
    expect(response).not_to have_http_status(:ok)
    expect(response).not_to redirect_to(start_url)
  end

  it 'preserves the legacy login and only shows the pilot button inside the allowlist' do
    get admin_meta_integrations_path
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("form[action='#{admin_meta_connection_path}'][method='post']")).to be_present
    expect(document.at_css("form[action='#{admin_user_facebook_omniauth_authorize_path}'][method='post']")).to be_present
    ENV['META_CENTRAL_CONNECT_ENABLED'] = 'false'
    get admin_meta_integrations_path
    document = Nokogiri::HTML(response.body)
    expect(document.at_css("form[action='#{admin_meta_connection_path}']")).to be_nil
    expect(document.at_css("form[action='#{admin_user_facebook_omniauth_authorize_path}'][method='post']")).to be_present
  end

  it 'rejects expired returns without redeeming credentials' do
    expect(client).not_to receive(:redeem)
    post admin_meta_connection_path
    travel 11.minutes do
      get admin_meta_connection_path, params: {oauth_handoff: 'c' * 64}
    end
    expect(response).to redirect_to(admin_meta_integrations_path)
  end

end
