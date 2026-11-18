require 'rails_helper'

RSpec.describe Instagram::SearchContext do
  let(:lead) { create(:lead, skip_automatic_routing: true) }
  def say(text, direction: 'inbound')
    lead.instagram_messages.create!(body: text, direction: direction, message_id: SecureRandom.uuid, occurred_at: Time.current)
  end
  def capture
    described_class.new(lead).capture!
  end

  it 'consolida os fragmentos reais de locação sem transformar 3 em código ou perder o teto' do
    say('Aluguel?')
    say('Apartamento')
    search = capture.remember!('transaction_type' => 'aluguel', 'category' => ['Apartamento'], 'city' => ['Praia Brava - Itajaí'])
    expect(search.business_type).to be_nil
    say('Qual a faixa de preço do aluguel?', direction: 'outbound')
    say('Até uns 12')
    say('C taxas')
    search = capture.remember!('city' => ['Barra Sul - Balneário Camboriú'])
    say('Quantos quartos você gostaria?', direction: 'outbound')
    say('3')
    say('Seria anual')
    search = capture
    expect(search.filters).to include('transaction_type' => 'rent', 'property_type' => 'Apartamento',
      'city' => 'Balneário Camboriú', 'neighborhood' => 'Barra Sul', 'price_max' => 12_000.0, 'bedrooms_min' => 3)
    expect(search.state).to include('includes_fees' => true, 'rental_period' => 'annual', 'business_type' => 'locacao')
    expect(search).to be_sufficient
    expect(InstagramMessage.property_codes_in('3')).to be_empty
    expect(InstagramMessage.property_codes_in('Cód. 3')).to eq(['3'])
    expect(Instagram::Qualification.capture!(lead)).to include('ready' => true, 'business_type' => 'locacao')
  end

  it 'mantém critérios fora da janela curta e zera filtros em uma nova busca explícita' do
    say('Procuro alugar apartamento de 3 quartos até 12 mil')
    capture.remember!('city' => ['Centro - Itajaí'])
    65.times { say('Obrigado') }
    expect(capture.filters).to include('price_max' => 12_000.0, 'city' => 'Itajaí')
    say('Procuro outras casas para comprar em outra cidade')
    expect(capture.filters).to include('transaction_type' => 'sale', 'property_type' => 'Casa')
    expect(capture.filters.keys).not_to include('price_max', 'city', 'bedrooms_min')
  end

  it 'não transforma pergunta, negativa ou legenda em intenção confirmada' do
    say('', direction: 'inbound').update!(context: {'attachments' => [{'title' => 'Comprar apartamento de 3 quartos até 12 mil'}]})
    say('Aluguel?')
    expect(capture.business_type).to be_nil
    say('Não quero alugar')
    expect(Instagram::Qualification.capture!(lead)['ready']).to be(false)
  end

  it 'distingue correção de orçamento e números com separador de milhares' do
    say('Quero alugar apartamento até R$ 120.000')
    expect(capture.filters['price_max']).to eq(120_000)
    say('Até 18 mil')
    expect(capture.filters['price_max']).to eq(18_000)
  end

  it 'limita o estado ao cursor do turno e à conta do lead' do
    first = say('Quero alugar apartamento até 12 mil')
    say('Procuro comprar uma casa')
    other = create(:lead, skip_automatic_routing: true)
    search = described_class.new(lead).capture!(through: first.id)
    expect(search.business_type).to eq('locacao')
    expect(other.reload.other_information).not_to have_key(described_class::KEY)
  end
end
