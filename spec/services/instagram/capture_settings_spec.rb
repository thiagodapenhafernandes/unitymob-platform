require 'rails_helper'

RSpec.describe Instagram::CaptureSettings do
  let(:integration) { create(:user_meta_integration) }
  let(:page) { create(:meta_facebook_page, user_meta_integration: integration, instagram_id: '11111') }
  let(:settings) { described_class.new(page, tenant: integration.tenant) }

  it 'fornece padrões sem exigir configuração e preserva desativação explícita' do
    expect(settings.rules.fetch('default')).to include('enabled' => true, 'sdr_enabled' => true, 'typing_enabled' => true)
    expect(settings.rules.dig('default', 'conditions').size).to eq(2)
    settings.save_many(campaign_ids: ['default'], create_only: false, rule: {'enabled' => false, 'data_access' => []})
    expect(settings.rules.fetch('default')).to include('enabled' => false, 'data_access' => [])
  end

  it 'herda o padrão e permite exceções por campanha sem alterar as outras regras' do
    settings.save_many(campaign_ids: ['default'], create_only: false, rule: {'missing_phone' => 'Qual seu telefone?', 'data_access' => ['details']})
    settings.save_many(campaign_ids: ['22222'], create_only: false, rule: {'property_code' => 'ABC', 'typing_enabled' => false})
    expect(settings.rules.fetch('22222')).to include('missing_phone' => 'Qual seu telefone?', 'data_access' => ['details'], 'typing_enabled' => false)
    expect(settings.rules.dig('default', 'typing_enabled')).to be(true)
  end
  it 'preserva a referência do lead ao indicar o catálogo sem imóvel identificado' do
    lead = create(:lead, tenant: integration.tenant, instagram_scoped_id: '12345')
    allow(lead.tenant).to receive(:public_base_url).and_return('https://catalogo.example')
    text = described_class.message({}, 'identify_property', lead)
    url = text[/https:\/\/[^\s]+/].delete_suffix('.')
    token = Instagram::PropertyJourney.token_from_url(url)
    expect(Instagram::PropertyJourney.resolve(lead.tenant, token)).to eq(lead)
  end

end
