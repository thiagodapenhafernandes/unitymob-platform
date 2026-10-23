require 'rails_helper'

RSpec.describe LeadConversationChannel, type: :channel do
  let(:tenant) { Tenant.create!(name: "Chat", slug: "chat-#{SecureRandom.hex(5)}") }
  let(:profile) { tenant.profiles.create!(name: 'Chat', axis: 'vertical', position: 700, permissions: { 'leads' => { 'view' => true, 'scope' => 'own' } }) }
  let(:agent) { create(:admin_user, tenant: tenant, profile: profile) }
  let(:lead) { create(:lead, tenant: tenant, admin_user: agent) }
  before { stub_connection(current_admin_user: agent) }

  it 'abre stream apenas da conversa autorizada' do
    subscribe(lead_id: lead.id, tenant_id: tenant.id)
    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_from(described_class.stream_name(lead))
  end

  it 'recusa outro dono' do
    lead.update!(admin_user: create(:admin_user, tenant: tenant))
    subscribe(lead_id: lead.id, tenant_id: tenant.id)
    expect(subscription).to be_rejected
  end

  it 'recusa outra conta mesmo com lead conhecido' do
    other = create(:lead, tenant: Tenant.create!(name: "Outra", slug: "chat-other-#{SecureRandom.hex(5)}"))
    subscribe(lead_id: other.id, tenant_id: other.tenant_id)
    expect(subscription).to be_rejected
  end

  it 'preserva o acesso de equipe no mesmo tenant' do
    allow(agent).to receive(:can_view_team?).with(:leads).and_return(true)
    owner = create(:admin_user, tenant: tenant)
    allow(agent).to receive(:team_scope_ids).and_return([agent.id, owner.id])
    lead.update!(admin_user: owner)
    subscribe(lead_id: lead.id, tenant_id: tenant.id)
    expect(subscription).to be_confirmed
  end

  it 'recusa ausência de permissão' do
    allow(agent).to receive(:can?).with(:view, :leads).and_return(false)
    subscribe(lead_id: lead.id, tenant_id: tenant.id)
    expect(subscription).to be_rejected
  end
end
