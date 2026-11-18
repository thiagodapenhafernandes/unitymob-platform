require 'rails_helper'

RSpec.describe Ai::PropertySearch::PublicQuery do
  let(:tenant) { Tenant.default }
  let(:setting) { PropertySetting.instance(tenant: tenant) }

  before do
    setting.update!(ai_property_search_allowed_fields: %w[transaction_type property_type city price])
    allow(described_class).to receive(:available?).with(tenant: tenant).and_return(true)
  end

  it 'preserva critérios anteriores e normaliza a resposta sem liberar campos desautorizados' do
    current = {'transaction_type' => 'rent', 'property_type' => 'Apartamento', 'price_max' => 12000}
    interpreter = instance_double(Ai::PropertySearch::Interpreter,
      call: Struct.new(:filters).new({'city' => 'Itajaí', 'developer_name' => 'Privado'}))
    expect(Ai::PropertySearch::Interpreter).to receive(:new)
      .with(setting: setting, text: 'Itajaí', voice: false, current_filters: current).and_return(interpreter)
    result = described_class.new(tenant: tenant, text: 'Itajaí', current_filters: current).call
    expect(result.params).to include('transaction_type' => 'aluguel', 'category' => ['Apartamento'], 'max_price' => '12000', 'city' => ['Itajaí'])
    expect(result.params.to_s).not_to include('Privado')
  end

  it 'mantém a chamada pública sem contexto e sem gravar memória de conversa' do
    interpreter = instance_double(Ai::PropertySearch::Interpreter,
      call: Struct.new(:filters).new({'property_type' => 'Casa'}))
    expect(Ai::PropertySearch::Interpreter).to receive(:new)
      .with(setting: setting, text: 'Casa', voice: false).and_return(interpreter)
    expect(described_class.new(tenant: tenant, text: 'Casa').call.params).to eq('category' => ['Casa'])
  end
end
