require 'rails_helper'

RSpec.describe Instagram::ConversationCondition do
  let(:lead) { create(:lead) }
  let(:history) { [{role: 'cliente', text: 'Quero visitar outro apartamento'}] }
  let(:fixed) { {'title' => 'Visitas', 'match' => 'keywords', 'keywords' => 'visitar;agendar', 'enabled' => true, 'ai_enabled' => false, 'action' => 'fixed', 'response' => 'Vamos agendar!'} }

  it 'aplica a primeira condição e ignora as desativadas em qualquer etapa' do
    lead.update_columns(other_information: {'instagram_capture' => {'step' => 'phone'}})
    rule = {'conditions' => [fixed.merge('enabled' => false), fixed, {'match' => 'always', 'enabled' => true}]}
    expect(described_class.match(lead, rule, history)).to eq(fixed)
    expect(described_class.match(lead, {'conditions' => []}, history)).to be_nil
  end

  it 'usa a IA para reconhecer a intenção pelo histórico sem gerar uma resposta livre' do
    provider = instance_double(Ai::Provider, api_key: 'test', resolved_model: 'test')
    client = instance_double(OpenAi::Client)
    allow(Ai::Provider).to receive(:active).and_return(provider)
    allow(Ai::Provider).to receive(:build_client).and_return(client)
    condition = fixed.merge('match' => 'context', 'keywords' => '', 'ai_enabled' => true)
    expect(client).to receive(:create_response).with(hash_including(store: false, input: include('visitar outro apartamento'))).and_return({'output_text' => '{"condition_id":"0"}'})
    expect(described_class.match(lead, {'conditions' => [condition]}, history)).to eq(condition)
  end
  it 'não encaminha uma recusa explícita de atendimento humano' do
    expect(described_class.human_requested?('Não quero falar com corretor agora')).to be(false)
    expect(described_class.human_requested?('Pode me passar para um corretor?')).to be(true)
  end

end
