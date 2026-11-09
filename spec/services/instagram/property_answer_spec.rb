require 'rails_helper'

RSpec.describe Instagram::PropertyAnswer do
  let(:lead) { create(:lead, client_name: "Maria Silva", phone: "5547998887777") }
  let(:property) { create(:habitation, tenant: lead.tenant, aceita_financiamento_flag: true, aceita_parcelamento_flag: true, numero_prestacoes: 24, condicoes_negociacao: 'Entrada de R$ 100.000,00; saldo em 24 parcelas.', saldo_devedor_cents: 987654321) }
  let(:rule) { {'property_code' => property.codigo} }
  let(:provider) { instance_double(Ai::Provider, api_key: 'test-only', resolved_model: 'test-model') }
  let(:client) { instance_double(OpenAi::Client) }
  let(:response) { {'facts' => ['financing', 'installments'], 'needs_broker' => false} }

  before do
    allow(Ai::Provider).to receive(:active).with(tenant: lead.tenant).and_return(provider)
    allow(Ai::Provider).to receive(:build_client).with(tenant: lead.tenant).and_return(client)
    allow(client).to receive(:create_response) do |payload|
      @payload = JSON.parse(payload.fetch(:input))
      {'output_text' => response.to_json}
    end
  end

  def answer(question = 'Como é a forma de pagamento?')
    described_class.new(lead, property, rule).call([{role: 'cliente', text: question}])
  end

  it 'não responde antes dos dados obrigatórios nem usa imóvel de outra conta' do
    lead.update_columns(client_name: nil)
    expect(answer).to eq(Instagram::CatalogReply::HANDOFF)
    expect(client).not_to have_received(:create_response)
    lead.update_columns(client_name: 'Maria Silva')
    other = Tenant.create!(name: 'Outra', slug: "ig-facts-#{SecureRandom.hex(3)}")
    foreign = create(:habitation, tenant: other)
    expect(described_class.new(lead, foreign, rule).call([{role: 'cliente', text: 'Qual o valor?'}])).to eq(Instagram::CatalogReply::HANDOFF)
  end

  it 'usa a IA para selecionar fatos e devolve somente dados reais do imóvel' do
    expect(answer).to include('aceita financiamento', '24 vezes')
    expect(@payload.fetch('registered_facts')).not_to have_key('terms')
    expect(@payload.to_json).not_to include('987654321', 'Entrada de R$ 100.000')
  end

  it 'encaminha entrada e juros não cadastrados em vez de inventar valores' do
    expect(answer('Qual é a entrada?')).to eq(Instagram::CatalogReply::HANDOFF)
    expect(answer('Qual é a taxa de juros?')).to eq(Instagram::CatalogReply::HANDOFF)
    expect(client).not_to have_received(:create_response)
  end

  context 'com condições explicitamente autorizadas para o imóvel da campanha' do
    let(:rule) { {'property_code' => property.codigo, 'use_registered_payment_conditions' => true} }
    let(:response) { {'facts' => ['terms'], 'needs_broker' => false, 'answer' => 'Inventado: entrada de 1 real'} }

    it 'usa o texto autorizado e ignora texto livre que o modelo tente devolver' do
      result = answer('Qual é a entrada?')
      expect(result).to include(property.condicoes_negociacao)
      expect(result).not_to include('Inventado')
    end

    it 'não aplica a autorização a outro imóvel fora da campanha' do
      rule['property_code'] = 'outro-codigo'
      expect(answer('Qual é a entrada?')).to eq(Instagram::CatalogReply::HANDOFF)
    end
  end

  context 'quando a IA não encontra dados suficientes' do
    let(:response) { {'facts' => [], 'needs_broker' => true} }
    it('encaminha ao corretor') { expect(answer).to eq(Instagram::CatalogReply::HANDOFF) }
  end

  context 'quando o modelo tenta citar um fato não permitido' do
    let(:response) { {'facts' => ['invented_discount'], 'needs_broker' => false} }
    it('recusa a resposta') { expect(answer).to eq(Instagram::CatalogReply::HANDOFF) }
  end

  it 'não transforma flags falsas por padrão em uma negativa comercial confirmada' do
    property.update!(aceita_financiamento_flag: false, aceita_parcelamento_flag: false)
    expect(answer).to eq(Instagram::CatalogReply::HANDOFF)
    expect(client).not_to have_received(:create_response)
  end

  it 'encaminha em falha do provedor sem impedir o atendimento' do
    allow(client).to receive(:create_response).and_raise(Timeout::Error)
    expect(answer).to eq(Instagram::CatalogReply::HANDOFF)
  end
  it 'não fornece ao modelo dados que a integração não autorizou' do
    rule['data_access'] = ['details']
    property.update!(dormitorios_qtd: 3)
    allow(client).to receive(:create_response) do |payload|
      facts = JSON.parse(payload.fetch(:input)).fetch('registered_facts')
      expect(facts.keys - %w[bedrooms suites parking area]).to be_empty
      {'output_text' => {'facts' => ['bedrooms'], 'needs_broker' => false}.to_json}
    end
    expect(answer('Quantos quartos?')).to include('Dormitórios: 3')
    expect(answer('Qual a forma de pagamento?')).to eq(Instagram::CatalogReply::HANDOFF)
  end

end
