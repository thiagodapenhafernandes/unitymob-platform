require 'rails_helper'

RSpec.describe Portal::LeadGatewayClient do
  let(:integration) { PortalIntegration.for_portal!('zapimoveis', tenant: Tenant.default) }
  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('APP_HOST').and_return('https://crm.example.com')
    allow(ENV).to receive(:fetch).with('APP_HOST').and_return('https://crm.example.com')
    allow(Meta::WebhookGatewayClient).to receive(:gateway_url).and_return('https://gateway.example.com')
    allow(Meta::WebhookGatewayClient).to receive(:internal_token).and_return('internal-token')
    allow(Meta::WebhookGatewayClient).to receive(:forwarding_secret).and_return('s' * 32)
  end

  it 'sends the stable destination and pause state to the gateway' do
    response = instance_double(HTTParty::Response, success?: true, body: '{"receiving_configured":true}')
    allow(HTTParty).to receive(:post).and_return(response)
    described_class.sync!(integration)
    expect(HTTParty).to have_received(:post) do |url, options|
      expect(url).to eq('https://gateway.example.com/internal/grupozap/routes')
      data = JSON.parse(options[:body])
      expect(data['client_key']).to eq(integration.lead_route_key)
      expect(data['target_url']).to end_with("/grupozap/#{integration.lead_route_key}")
      expect(data['active']).to eq(false)
    end
  end

  it 'does not claim readiness without Grupo OLX authentication at the gateway' do
    response = instance_double(HTTParty::Response, success?: true, body: '{"receiving_configured":false}')
    allow(HTTParty).to receive(:post).and_return(response)
    expect { described_class.sync!(integration) }.to raise_error(/Autenticação/)
  end
end
