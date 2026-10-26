require 'rails_helper'

RSpec.describe 'Contexto dos eventos do sino' do
  let(:owner) { create(:admin_user, :admin) }
  let(:lead) { create(:lead, tenant: owner.tenant, admin_user: owner) }
  before { allow_any_instance_of(Lead).to receive(:route_lead) }

  it 'retorna uma consulta vazia sem usuário ou conta' do
    InAppNotification.create!(admin_user: owner, tenant: owner.tenant, kind: 'appointment', title: 'Privada')

    expect(InAppNotification.visible_for(owner, nil).recent.to_a).to be_empty
    expect(InAppNotification.visible_for(nil, owner.tenant).unread.count).to eq(0)
    expect(InAppNotification.title_count_for(owner, nil)).to eq(0)
  end

  it 'limita as notificações ao destinatário e à conta informados' do
    other = create(:admin_user, :admin)
    notice = InAppNotification.create!(admin_user: owner, tenant: owner.tenant, kind: 'appointment', title: 'Privada')
    InAppNotification.create!(admin_user: other, tenant: other.tenant, kind: 'appointment', title: 'Outro destinatário')

    expect(InAppNotification.visible_for(owner, owner.tenant)).to contain_exactly(notice)
    other_tenant = Tenant.create!(name: 'Outra conta', slug: SecureRandom.hex(8))
    expect(InAppNotification.visible_for(owner, other_tenant)).to be_empty
  end

  it 'identifica apenas a primeira entrada após saída como nova resposta no Direct' do
    time = Time.current
    lead.instagram_messages.create!(message_id: 'out', direction: 'outbound', occurred_at: time)
    lead.instagram_messages.create!(message_id: 'in', direction: 'inbound', occurred_at: time + 1)
    lead.instagram_messages.create!(message_id: 'in-more', direction: 'inbound', occurred_at: time + 2)
    expect(InAppNotification.where(admin_user: owner).order(:id).map { |n| n.metadata['event'] }).to eq(%w[message_reply instagram_message])
  end

  it 'não interpreta saída falha como resposta no WhatsApp' do
    conversation = WhatsappConversation.create!(tenant: owner.tenant, assigned_admin_user: owner, contact_phone: '5547999990077')
    outgoing = conversation.messages.create!(tenant: owner.tenant, direction: 'outbound', status: 'failed', body: 'saída')
    incoming = conversation.messages.create!(tenant: owner.tenant, direction: 'inbound', body: 'entrada')
    expect(InAppNotification.notify_whatsapp_message!(conversation, incoming).metadata['event']).to eq('whatsapp_message')
    outgoing.update!(status: 'sent')
    expect(InAppNotification.notify_whatsapp_message!(conversation, incoming).metadata['event']).to eq('message_reply')
  end

  it 'publica contexto de lead só para destinatário da mesma conta com acesso' do
    notice = InAppNotification.notify_lead!(lead, owner, event: 'lead_new', title: 'Novo lead')
    expect(notice.metadata).to include('event' => 'lead_new', 'lead_id' => lead.id)
    other = create(:admin_user, :admin, tenant: Tenant.create!(name: 'Outra', slug: SecureRandom.hex(8)))
    expect { InAppNotification.notify_lead!(lead, other, event: 'lead_new', title: 'Privado') }.not_to change(InAppNotification, :count)
    allow(owner).to receive(:can?).with(:view, :leads).and_return(false)
    expect(InAppNotification.visible_for(owner, owner.tenant)).not_to include(notice)
  end
end
