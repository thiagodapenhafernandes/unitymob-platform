require 'rails_helper'
RSpec.describe Support::Exchange do
  let(:account) { Support::Account.create!(uid: SecureRandom.uuid, local_tenant_id: 91, name: 'Salute', endpoint: 'https://admin.unitymob.com.br', secret: 's' * 64) }
  let(:ticket) { account.tickets.create!(subject: 'Erro', requester_id: '12', requester_name: 'Maria', intake: Support::Ticket::QUESTIONS.keys.index_with { 'Detalhes' }) }
  def snapshot(revision, status, body)
    { 'event_id' => SecureRandom.uuid, 'kind' => 'snapshot', 'ticket' => ticket.attributes.slice(*described_class::TICKET_FIELDS).merge('revision' => revision, 'status' => status), 'message' => { 'uid' => SecureRandom.uuid, 'side' => 'support', 'author' => 'Ana', 'body' => body, 'files' => [] } }
  end
  it 'mantém mensagens atrasadas sem regredir o estado de resolução' do
    newer = snapshot(3, 'resolvido', 'Resolvido')
    older = snapshot(2, 'em_atendimento', 'Conferindo')
    described_class.receive(account, newer)
    described_class.receive(account, older)
    described_class.receive(account, newer)
    expect(ticket.reload.status).to eq('resolvido')
    expect(ticket.revision).to eq(3)
    expect(ticket.messages.count).to eq(2)
    expect(Support::Receipt.count).to eq(2)
  end
  it 'preserva entrega quando o destino cai e conclui após recuperação' do
    delivery = described_class.enqueue(ticket)
    allow(Support::Transport).to receive(:post).and_raise(Timeout::Error)
    Support::DispatchJob.perform_now
    expect(delivery.reload.delivered_at).to be_nil
    expect(delivery.attempts).to eq(1)
    delivery.update!(next_attempt_at: 1.second.ago)
    allow(Support::Transport).to receive(:post).and_return({})
    Support::DispatchJob.perform_now
    expect(delivery.reload.delivered_at).to be_present
  end
  it 'não envia mensagem seguinte antes da criação pendente' do
    first = described_class.enqueue(ticket)
    first.update!(next_attempt_at: 1.hour.from_now)
    following = described_class.enqueue(ticket)
    expect(Support::Transport).not_to receive(:post)
    Support::DispatchJob.perform_now
    expect(following.reload.delivered_at).to be_nil
  end
  it 'revoga grants ainda não consumidos e sessões do operador correto' do
    grant = Support::AccessSession.create!(account: account, ticket: ticket, requester_id: '12', operator_id: '7', operator_name: 'Ana', token_digest: 'a', redeem_before: 1.minute.from_now)
    described_class.receive(account, { 'event_id' => SecureRandom.uuid, 'kind' => 'revoke_access', 'operator_id' => '7', 'issued_at' => Time.current.iso8601(6) })
    expect(grant.reload.ended_at).to be_present
  end

  it 'marca recusa permanente sem perder a mensagem nem repetir indefinidamente' do
    delivery = described_class.enqueue(ticket)
    allow(Support::Transport).to receive(:post).and_raise(Support::Transport::DeliveryError.new('Resolvido', status: 409))
    Support::DispatchJob.perform_now
    expect(delivery.reload.failed_at).to be_present
    expect(delivery.delivered_at).to be_nil
    expect(ticket.reload).to be_failed
    expect(Support::Delivery.due).not_to include(delivery)
  end

  it 'não reaplica uma desativação antiga depois de reativar a conta' do
    described_class.receive(account, { 'event_id' => SecureRandom.uuid, 'kind' => 'account_state', 'active' => true, 'revision' => 2 })
    described_class.receive(account, { 'event_id' => SecureRandom.uuid, 'kind' => 'account_state', 'active' => false, 'revision' => 1 })
    expect(account.reload).to be_active
    expect(account.control_revision).to eq(2)
  end

end
