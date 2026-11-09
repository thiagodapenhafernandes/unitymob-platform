require 'rails_helper'

RSpec.describe Instagram::CaptureAnswer do
  it 'não transforma perguntas, imóveis, bairros ou saudações em nome' do
    ['Sobre esse apto do anúncio em cima do shopping.', 'Como é a forma de pagamento?', 'Quero uma casa',
     'Bom dia', 'Centro', 'Manda fotos', 'Não quero informar', 'Pular'].each do |text|
      expect(described_class.new(text).name).to be_nil, text
    end
  end

  it 'captura nome simples, identificação explícita e telefone em uma frase' do
    expect(described_class.new('Edna de Azevedo').name).to eq('Edna de Azevedo')
    text = described_class.new('Me chamo Edna e meu WhatsApp é (47) 99888-7777')
    expect(text.name).to eq('Edna')
    expect(text.phone).to eq('5547998887777')
    expect(described_class.new('Sou Edna').name).to eq('Edna')
    combined = described_class.new('Edna Azevedo (47) 99888-7777')
    expect(combined.name).to eq('Edna Azevedo')
    expect(combined.phone).to eq('5547998887777')
    expect(described_class.new('Itajaí').name(explicit_only: true)).to be_nil
    expect(described_class.new('Valor R$ 47998887777').phone).to be_nil
    expect(described_class.new('Quero o imóvel 47998887777').phone).to be_nil
    expect(described_class.new('prefiro continuar por aqui').declined?).to be(true)
  end
end

RSpec.describe Instagram::CaptureSettings do
  it 'atualiza somente os prompts antigos padrão e preserva os personalizados' do
    defaults = described_class.prompts({'name_prompt' => 'Olá! Como posso chamar você?',
      'phone_prompt' => 'Qual é o seu telefone com DDD para nossa equipe continuar o atendimento?'})
    expect(defaults['name_prompt']).to eq(described_class::DEFAULT_NAME_PROMPT)
    expect(defaults['phone_prompt']).to eq(described_class::DEFAULT_PHONE_PROMPT)
    expect(described_class.prompts({'name_prompt' => 'Como prefere ser chamado?'})['name_prompt']).to eq('Como prefere ser chamado?')
  end
end
