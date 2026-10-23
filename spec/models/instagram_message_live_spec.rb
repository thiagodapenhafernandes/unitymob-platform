require 'rails_helper'
RSpec.describe InstagramMessage do
  let(:lead) { create(:lead) }
  it 'notifica mensagens recebidas e enviadas sem transmitir conteúdo ou contatos' do
    allow(ActionCable.server).to receive(:broadcast)
    %w[inbound outbound].each do |direction|
      lead.instagram_messages.create!(message_id: SecureRandom.uuid, body: 'Privado', direction: direction, occurred_at: Time.current)
    end
    expect(ActionCable.server).to have_received(:broadcast).with(LeadConversationChannel.stream_name(lead), {refresh: true}).twice
  end
  it 'uma falha do Redis não perde a mensagem já recebida' do
    allow(ActionCable.server).to receive(:broadcast).and_raise(IOError)
    message = lead.instagram_messages.create!(message_id: SecureRandom.uuid, body: 'Privado', occurred_at: Time.current)
    expect(message.reload.body).to eq('Privado')
  end
end
