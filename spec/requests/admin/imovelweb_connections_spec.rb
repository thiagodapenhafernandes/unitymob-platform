require 'rails_helper'

RSpec.describe 'Imovelweb binding workspace', type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  before { host! 'localhost'; sign_in admin }

  def connection(tenant: admin.tenant, **attrs)
    ImovelwebConnection.create!({ tenant: tenant, environment: 'production', client_code: SecureRandom.uuid }.merge(attrs))
  end

  it 'shares the block between both Imovelweb tabs without creating a connection on GET' do
    %w[imovelweb imovelweb_2].each do |portal|
      expect { get admin_portal_integrations_path(portal: portal) }.not_to change(ImovelwebConnection, :count)
      expect(response).to have_http_status(:ok)
      block = Nokogiri::HTML(response.body).at_css('#portal-imovelweb-leads')
      expect(block.text).to include('Conectar conta anunciante', 'confirmação e a ativação acontecem automaticamente')
      expect(block.css('input[name="imovelweb_connection[advertiser_code]"]').size).to eq(1)
      expect(block.css('input[type=password], input[name*=enabled], input[name*=authorized], input[name*=client_secret]')).to be_empty
    end
  end

  it 'saves only the account code, deduplicates requests and never authorizes or activates' do
    attrs = { advertiser_code: ' 47294717 ', tenant_id: Tenant.create!(name: 'Outra conta', slug: SecureRandom.hex(8)).id, client_code: 'injected', enabled: true, authorized_at: Time.current, environment: 'sandbox', client_secret: 'do-not-store' }
    expect(Imovelweb::GatewayClient).not_to receive(:sync!)
    post admin_imovelweb_connections_path, params: { imovelweb_connection: attrs }
    expect(response).to redirect_to(admin_portal_integrations_path(portal: 'imovelweb', anchor: 'portal-imovelweb-leads'))
    c = ImovelwebConnection.last
    expect(c).to have_attributes(tenant_id: admin.tenant_id, advertiser_code: '47294717', environment: 'production', enabled: false, authorized_at: nil)
    expect(c.client_code).to start_with('um-')
    expect { post admin_imovelweb_connections_path, params: { imovelweb_connection: attrs } }.not_to change(ImovelwebConnection, :count)
    patch admin_imovelweb_connection_path(c), params: { imovelweb_connection: { advertiser_code: 'updated', enabled: true } }
    expect(c.reload).to have_attributes(advertiser_code: 'updated', enabled: false, authorized_at: nil)
  end

  it 'rejects blank, oversized or malformed codes without leaving drafts' do
    ['', 'x' * 129, '<script>'].each do |code|
      expect { post admin_imovelweb_connections_path, params: { imovelweb_connection: { advertiser_code: code } } }.not_to change(ImovelwebConnection, :count)
      expect(flash[:alert]).to be_present
    end
  end

  it 'isolates records, receipt counts and edits by tenant' do
    own = connection(advertiser_code: 'own-account')
    foreign = connection(tenant: Tenant.create!(name: 'Outra conta', slug: SecureRandom.hex(8)), advertiser_code: 'foreign-account')
    ImovelwebLeadReceipt.create!(imovelweb_connection: foreign, event_id: 'foreign-event', event_type: 'CONTACTO', payload: '{}', status: 'processed', received_at: Time.current)
    get admin_portal_integrations_path(portal: 'imovelweb')
    expect(response.body).to include('own-account')
    expect(response.body).to include('0 processados')
    expect(response.body).not_to include('foreign-account', foreign.client_code, foreign.route_key)
    patch admin_imovelweb_connection_path(foreign), params: { imovelweb_connection: { advertiser_code: 'stolen' } }
    expect(response).to have_http_status(:not_found)
    expect(foreign.reload.advertiser_code).to eq('foreign-account')
    expect(own.reload.enabled).to be(false)
  end

  it 'does not edit sandbox or authorized identities' do
    [connection(environment: 'sandbox'), connection(authorized_at: Time.current), connection(enabled: true)].each do |c|
      patch admin_imovelweb_connection_path(c), params: { imovelweb_connection: { advertiser_code: 'changed' } }
      expect(flash[:alert]).to be_present
      expect(c.reload.advertiser_code).to be_nil
    end
  end

  it 'requires integration management permission' do
    sign_out admin
    viewer = create(:admin_user, tenant: admin.tenant, profile: admin.tenant.profiles.find_by!(key: 'agent'), role: :editor)
    sign_in viewer
    expect { post admin_imovelweb_connections_path, params: { imovelweb_connection: { advertiser_code: 'blocked' } } }.not_to change(ImovelwebConnection, :count)
    expect(response).to redirect_to(admin_root_path)
  end
  it 'loads the official authorization for an owned connection only, without activating on GET' do
    own = connection(client_code: "um-#{SecureRandom.uuid}")
    url = "https://loginbr-open.navent.com/official-integrator/#{own.client_code}.js"
    allow(Imovelweb::GatewayClient).to receive(:authorization_script).with(own).and_return(url)
    get authorization_admin_imovelweb_connection_path(own)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="opennavent"', url)
    expect(own.reload.authorized_at).to be_nil
    foreign = connection(tenant: Tenant.create!(name: 'Outra conta', slug: SecureRandom.hex(8)))
    get authorization_admin_imovelweb_connection_path(foreign)
    expect(response).to have_http_status(:not_found)
    post verify_admin_imovelweb_connection_path(foreign)
    expect(response).to have_http_status(:not_found)
  end

  it 'verifies consent server-side and enqueues automatic confirmation while pending' do
    own = connection(client_code: "um-#{SecureRandom.uuid}")
    allow(Imovelweb::ActivateConnection).to receive(:call).with(own).and_return(false)
    expect { post verify_admin_imovelweb_connection_path(own), params: { enabled: true, tenant_id: 123 } }.to have_enqueued_job(ImovelwebConnectionActivationJob).with(own.id)
    expect(own.reload.enabled).to be(false)
    expect(own.authorization_requested_at).to be_present
    expect(flash[:notice]).to include('Aguardando')
  end

  it 'keeps publication and receiving settings in separate forms without technical credentials' do
    get admin_portal_integrations_path(portal: 'imovelweb')
    doc = Nokogiri::HTML(response.body)
    expect(doc.at_css('#portal-publication form')['action']).to eq(admin_portal_integration_path('imovelweb'))
    expect(doc.at_css('#portal-imovelweb-leads form')['action']).to eq(admin_imovelweb_connections_path)
    expect(doc.at_css('#portal-publication input[name="portal_integration[enabled]"]')).to be_present
    expect(doc.css('#portal-imovelweb-leads input[name*=enabled]')).to be_empty
    expect(doc.css('input[type=password]')).to be_empty
    expect(doc.css('.ax-mobile-detail-header')).to be_present
  end

end
