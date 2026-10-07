require 'rails_helper'

RSpec.describe PortalLeadGatewaySyncJob do
  let(:integration) { PortalIntegration.for_portal!('zapimoveis', tenant: Tenant.default) }

  it 'persists a stable identity and confirms synchronization' do
    allow(Portal::LeadGatewayClient).to receive(:sync!).with(integration)
    key = integration.lead_route_key
    described_class.perform_now(integration.id)
    expect(integration.reload.lead_route_key).to eq(key)
    expect(integration.lead_gateway_synced_at).to be_present
    expect(integration.lead_gateway_error).to be_nil
  end

  it 'stores a safe message and schedules another attempt' do
    allow(Portal::LeadGatewayClient).to receive(:sync!).and_raise('private failure')
    expect { described_class.perform_now(integration.id) }.to have_enqueued_job(described_class)
    expect(integration.reload.lead_gateway_error).to include('automaticamente')
    expect(integration.lead_gateway_error).not_to include('private failure')
  end
end
