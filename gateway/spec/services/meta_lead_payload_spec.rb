require_relative '../../app/services/meta_lead_payload'
RSpec.describe Gateway::MetaLeadPayload do
  it "separa mensagens Instagram por perfil sem vazar o restante do lote" do
    payload = {'object'=>'instagram','entry'=>[{'id'=>'a','messaging'=>[{'message'=>{'mid'=>'1'}}]},{'id'=>'b','messaging'=>[{'message'=>{'mid'=>'2'}}]}]}
    contexts = described_class.extract_event_contexts(payload)
    expect(contexts.map { |c| c[:page_id] }).to eq(['a', 'b'])
    expect(contexts.first[:payload]['entry']).to eq([payload['entry'].first])
  end
  it "mantém o roteamento de formulários" do
    payload = {'entry'=>[{'changes'=>[{'field'=>'leadgen','value'=>{'leadgen_id'=>'x','page_id'=>'p','form_id'=>'f'}}]}]}
    expect(described_class.extract_event_contexts(payload).first).to include(event_type: 'leadgen', page_id: 'p', form_id: 'f')
  end
end
