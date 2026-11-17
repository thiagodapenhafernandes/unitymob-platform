require 'rails_helper'

RSpec.describe ExternalLeadMigration::SyncInstagramQualificationJob do
  let(:tenant) { Tenant.default }
  let!(:integration) { create(:external_lead_integration, tenant: tenant, export_enabled: true) }
  let(:lead) { create(:lead, tenant: tenant, skip_automatic_routing: true, c2s_export_external_id: '123',
    other_information: {'instagram_qualification' => {'ready' => true, 'business_type' => 'locacao',
      'request' => 'Apartamento no Centro, 2 quartos', 'next_step' => 'Visitar'}}) }
  let(:api) { instance_double(ExternalLeadMigration::Client) }
  before { allow(ExternalLeadMigration::Client).to receive(:new).and_return(api) }

  it 'não envia qualificação de locação quando somente venda está permitida, inclusive no espelhamento' do
    integration.update!(outgoing_business_type: 'sale', mirror_c2s_owners: true)
    lead.update_columns(other_information: lead.other_information.merge('business_type' => 'locacao'))
    expect(api).not_to receive(:update_lead_routing)
    described_class.perform_now(tenant.id, lead.id)
    expect(lead.reload.other_information['instagram_c2s_qualification']).to be_nil
  end

  it 'não repete append com resultado incerto após timeout' do
    allow(api).to receive(:update_lead_routing).and_raise(Timeout::Error)
    expect { described_class.perform_now(tenant.id, lead.id) }.to raise_error(Timeout::Error)
    expect(lead.reload.other_information.dig('instagram_c2s_qualification', 'status')).to eq('uncertain')
    described_class.perform_now(tenant.id, lead.id)
    expect(api).to have_received(:update_lead_routing).once
  end

  it 'não envia entre contas, sem qualificação ou com integração desabilitada' do
    expect(api).not_to receive(:update_lead_routing)
    other = Tenant.create!(name: 'Outra', slug: 'sync-ig-other')
    described_class.perform_now(other.id, lead.id)
    integration.update!(enabled: false)
    described_class.perform_now(tenant.id, lead.id)
  end

  it 'preserva modalidade explícita da regra e não altera seller nem status' do
    rule = create(:distribution_rule, tenant: tenant, delivery_destination: 'c2s', c2s_negotiation_type: 'Compra')
    lead.update_columns(distribution_rule_id: rule.id)
    allow(api).to receive(:update_lead_routing).and_return('success' => true)
    described_class.perform_now(tenant.id, lead.id)
    expect(api).to have_received(:update_lead_routing).with('123', attributes: {'body' => include('Centro'), 'type_negotiation' => 0})
  end
end
