require 'rails_helper'

RSpec.describe 'Imovelweb received events', type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let!(:connection) { ImovelwebConnection.create!(tenant: admin.tenant, environment: 'production', client_code: 'portal-test', enabled: true, authorized_at: Time.current) }
  let!(:receipt) do
    ImovelwebLeadReceipt.create!(imovelweb_connection: connection, event_id: 'real-event', event_type: 'CONTACTO_MENSAJE', received_at: Time.current,
      status: 'quarantined', reason: 'unknown_listing', payload: { reference: '7975', listing_id: '3029491811', name: 'Teste', message: '<script>alert(1)</script>' }.to_json)
  end
  before do
    host! 'localhost'
    sign_in admin
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('IMOVELWEB_RECEIVING_ENABLED').and_return('true')
  end

  it 'reflects active production and the last received event on both tabs and the summary' do
    %w[imovelweb imovelweb_2 zapimoveis].each do |portal|
      get admin_portal_integrations_path(portal: portal)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Recebimento ativo em produção', I18n.l(receipt.received_at, format: :short))
      if portal.start_with?('imovelweb')
        expect(response.body).to include(admin_imovelweb_connection_lead_receipts_path(connection, status: 'quarantined'))
      end
    end
    connection.update!(enabled: false)
    get admin_portal_integrations_path(portal: 'imovelweb')
    expect(response.body).to include('Recebimento pausado')
    expect(response.body).not_to include('Recebimento ativo em produção')
  end

  it 'opens the quarantine and escaped details without writing or processing anything' do
    original = receipt.attributes
    expect(ImovelwebLeadProcessingJob).not_to receive(:perform_later)
    expect(Imovelweb::GatewayClient).not_to receive(:sync!)
    expect do
      get admin_imovelweb_connection_lead_receipts_path(connection, status: 'quarantined')
      expect(response.body).to include('real-event', 'Abrir evento', 'Em quarentena')
      get admin_imovelweb_connection_lead_receipt_path(connection, receipt)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('7975', '3029491811', 'Nenhum lead de carteira criado', '&lt;script&gt;')
      expect(response.body).not_to include('<script>alert(1)</script>')
      expect(Nokogiri::HTML(response.body).at_css('.ax-mobile-detail-header')).to be_present
    end.not_to change(Lead, :count)
    expect(receipt.reload.attributes).to eq(original)
  end

  it 'scopes both connection and receipt to the current tenant and connection' do
    foreign_tenant = Tenant.create!(name: 'Outra', slug: SecureRandom.hex(8))
    foreign = ImovelwebConnection.create!(tenant: foreign_tenant, environment: 'production', client_code: 'foreign')
    other = ImovelwebLeadReceipt.create!(imovelweb_connection: foreign, event_id: 'foreign-event', event_type: 'CONTACTO', received_at: Time.current, payload: '{}')
    get admin_imovelweb_connection_lead_receipts_path(foreign)
    expect(response).to have_http_status(:not_found)
    sign_in admin
    get admin_imovelweb_connection_lead_receipt_path(connection, other)
    expect(response).to have_http_status(:not_found)
    sign_in admin
    get admin_imovelweb_connection_lead_receipts_path(connection)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('foreign-event')
  end

  it 'requires integration management permission for index and details' do
    sign_out admin
    viewer = create(:admin_user, tenant: admin.tenant, profile: admin.tenant.profiles.find_by!(key: 'agent'), role: :editor)
    sign_in viewer
    [admin_imovelweb_connection_lead_receipts_path(connection), admin_imovelweb_connection_lead_receipt_path(connection, receipt)].each do |path|
      get path
      expect(response).to redirect_to(admin_root_path)
      expect(response.body).not_to include('real-event', '7975')
    end
  end
end
