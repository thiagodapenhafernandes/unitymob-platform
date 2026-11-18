require 'rails_helper'

RSpec.describe 'Continuidade do SDR Instagram' do
  let(:lead) { create(:lead, skip_automatic_routing: true) }
  let(:tenant) { lead.tenant }
  def message(text, direction: 'inbound')
    lead.instagram_messages.create!(body: text, direction: direction, message_id: SecureRandom.uuid, occurred_at: Time.current)
  end
  def rental(title, rent:, fees: 0, tax: 0, daily: false)
    property = build(:habitation, tenant: tenant, titulo_anuncio: title, categoria: 'Apartamento',
      status: daily ? 'Diária' : 'Aluguel', valor_venda_cents: 0, valor_locacao_cents: rent,
      valor_condominio_cents: fees, valor_iptu_cents: tax, dormitorios_qtd: 3,
      intake_modalidade: daily ? 'locacao_diaria' : 'locacao_anual')
    property.address.bairro = 'Barra Sul'
    property.address.bairro_comercial = 'Barra Sul'
    property.save!
    property
  end

  it 'informa a falta de opções compatíveis sem perguntar novamente a cidade já definida' do
    last = message('Quero alugar apartamento de 3 quartos até 12 mil')
    Instagram::SearchContext.new(lead).capture!.remember!('city' => ['Barra Sul - Balneário Camboriú'])
    query = instance_double(Ai::PropertySearch::PublicQuery, call: Ai::PropertySearch::PublicQuery::Result.new({}, nil, nil))
    allow(Ai::PropertySearch::PublicQuery).to receive(:new).and_return(query)
    result = Instagram::CatalogReply.new(lead, {}).call([{role: 'cliente', text: last.body, message_id: last.id}], first_turn: false)
    expect(result).to include('Não encontrei opções', 'ajustar o orçamento ou a região')
  end

  it 'aplica modalidade, quartos e teto com taxas mesmo quando a IA devolve um teto maior' do
    message('Quero alugar apartamento de 3 quartos até 12 mil')
    message('Com taxas')
    last = message('Anual')
    Instagram::SearchContext.new(lead).capture!.remember!('city' => ['Barra Sul - Balneário Camboriú'])
    within = rental('Compatível', rent: 750_000, fees: 83_000, tax: 42_000)
    expensive = rental('Fora do orçamento', rent: 1_900_000)
    total_expensive = rental('Taxas acima do teto', rent: 1_100_000, fees: 150_000)
    daily = rental('Temporada', rent: 360_000, daily: true)
    unknown = rental('Taxas sem confirmação', rent: 700_000, fees: nil, tax: nil)
    query = instance_double(Ai::PropertySearch::PublicQuery, call: Ai::PropertySearch::PublicQuery::Result.new({'max_price' => '19000'}, nil, nil))
    allow(Ai::PropertySearch::PublicQuery).to receive(:new).and_return(query)
    allow(Storage::PublicCdnImageUrl).to receive(:resolve).and_return(nil)
    result = Instagram::CatalogReply.new(lead, {}).call([{role: 'cliente', text: 'Anual', message_id: last.id}], first_turn: false)
    expect(result.body).to include('Compatível', '8.750')
    expect(result.body).not_to include(expensive.titulo_anuncio, total_expensive.titulo_anuncio, daily.titulo_anuncio, unknown.titulo_anuncio)
    audit = lead.activities.where(kind: 'instagram_sdr_decision').last.metadata
    expect(audit).to include('outcome' => 'catalog_results', 'returned_property_ids' => [within.id])
    expect(audit.dig('filters', 'price_max')).to eq(12_000.0)
  end

  it 'interpreta 3 como quartos após a pergunta, sem bloquear respostas posteriores em código antigo' do
    hidden = create(:habitation, :unavailable, tenant: tenant, codigo: '3')
    message('Quantos quartos?', direction: 'outbound')
    last = message('3')
    message('Anual')
    history = Instagram::CaptureJob.new.send(:conversation_history, lead, last.id)
    context = Instagram::PropertyContext.new(lead)
    expect(context.resolve(history)).to be_nil
    expect(context.unavailable).not_to eq(true)
    expect(Instagram::SearchContext.new(lead).capture!.filters['bedrooms_min']).to eq(3)
    expect(hidden).not_to be_exibir_no_site_flag
  end

  it 'preserva código pequeno quando o bot pediu explicitamente código' do
    property = create(:habitation, tenant: tenant, codigo: '3')
    history = [{role: 'assistente', text: 'Qual o código do imóvel?'}, {role: 'cliente', text: '3'}]
    expect(Instagram::PropertyContext.new(lead).resolve(history)).to eq(property)
  end

  it 'oferece continuação após indisponibilidade, sem voltar à mesma referência ao aceitar alternativas' do
    hidden = create(:habitation, :unavailable, tenant: tenant, codigo: '9776')
    message('Cód. 9776')
    expect(Instagram::CatalogReply.new(lead, {}).call([{role: 'cliente', text: 'Está disponível?'}], first_turn: false)).to include('não aparece como disponível')
    available = create(:habitation, tenant: tenant)
    query = instance_double(Ai::PropertySearch::PublicQuery, call: Ai::PropertySearch::PublicQuery::Result.new({}, nil, nil))
    allow(Ai::PropertySearch::PublicQuery).to receive(:new).and_return(query)
    result = Instagram::CatalogReply.new(lead, {}).call([
      {role: 'assistente', text: 'Esse anúncio não aparece como disponível no momento. Quer que eu procure outras opções?'},
      {role: 'cliente', text: 'Sim'}
    ], first_turn: false)
    expect(result.body).to include(available.titulo_anuncio.presence || "Imóvel #{available.codigo}")
    expect(result.body).not_to include(hidden.codigo)
  end

  it 'não captura local como nome enquanto o bot pergunta a região e aceita apresentação explícita' do
    reply = message('Qual cidade ou bairro você prefere?', direction: 'outbound')
    answer = message('Praia Brava')
    job = Instagram::CaptureJob.new
    expect(job.send(:capture_name, answer, {'step' => 'name'}, [reply])).to be_nil
    explicit = message('Me chamo Maria Silva')
    expect(job.send(:capture_name, explicit, {'step' => 'name'}, [reply])).to eq('Maria Silva')
  end
end
