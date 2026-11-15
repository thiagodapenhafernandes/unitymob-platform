require 'rails_helper'

RSpec.describe Instagram::Qualification do
  let(:lead) { create(:lead, skip_automatic_routing: true) }
  let(:property) { create(:habitation, tenant: lead.tenant, codigo: '9705', status: 'Venda') }
  def say(body, context: {})
    lead.instagram_messages.create!(body: body, context: context, message_id: SecureRandom.uuid, occurred_at: Time.current)
    described_class.capture!(lead)
  end

  it 'não qualifica compartilhamento, reação, dúvida, diária ou intenção negada' do
    say('', context: {'attachments' => [{'type' => 'ig_post', 'title' => "Cód. #{property.codigo}, quero comprar para investir"}]})
    ['😍', 'Ele financia? Com 600 de entrada', 'Quero diária até 500 reais', 'Não quero comprar'].each do |body|
      expect(say(body)['ready']).to be(false)
    end
  end

  it 'encerra a qualificação com imóvel ativo e um próximo passo real e resume sem contatos' do
    say('', context: {'property_code' => property.codigo})
    expect(say('Quero visitar esse apartamento')['ready']).to be(true)
    expect(described_class.summary(lead)).to include('Venda', '9705', 'Quero visitar', 'Próximo passo')
    say('Me chamo Maria, meu WhatsApp é (47) 99888-7777')
    expect(described_class.summary(lead)).not_to include('99888')
    expect(lead.other_information.dig('instagram_qualification', 'ready')).to be(true)
  end

  it 'qualifica busca mínima de locação sem atribuir o imóvel antigo da conversa' do
    say('', context: {'property_code' => property.codigo})
    result = say('Procuro alugar apartamento de 2 quartos no Centro até 4 mil')
    expect(result).to include('ready' => true, 'business_type' => 'locacao')
    expect(result['property_id']).to be_nil
    expect(say('Me chamo Maria')['property_id']).to be_nil
    expect(described_class.summary(lead)).to include('Locação', '2 quartos', 'Centro')
  end

  it 'respeita indisponibilidade, isolamento entre contas e intenção do proprietário' do
    foreign = create(:habitation, tenant: Tenant.create!(name: "Outra", slug: "qualification-other"), codigo: '887766', status: 'Venda')
    expect(say("Quero visitar o código #{foreign.codigo}")['ready']).to be(false)
    property.update_columns(status: 'Vendido')
    expect(say("Quero visitar o código #{property.codigo}")['ready']).to be(false)
    expect(say('Quero vender meu apartamento de 2 quartos')['ready']).to be(false)
    expect(say('Me chamo Maria')['ready']).to be(false)
  end
  it 'não reabre uma intenção negada apenas por receber um nome ou telefone' do
    expect(say('Procuro alugar apartamento de 2 quartos no Centro')['ready']).to be(true)
    expect(say('Não tenho interesse')['ready']).to be(false)
    expect(say('Me chamo Maria')['ready']).to be(false)
    expect(say('Quero comprar apartamento de 3 quartos no Centro')['ready']).to be(true)
  end

end
