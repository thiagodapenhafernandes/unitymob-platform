require 'rails_helper'

RSpec.describe Leads::CommercialReportFactsQuery do
  let(:tenant) { Tenant.default }
  let(:owner) { create(:admin_user, tenant: tenant) }
  let(:previous) { create(:admin_user, tenant: tenant) }
  let(:lead) { create(:lead, tenant: tenant, admin_user: nil, created_at: 1.year.ago, skip_automatic_routing: true) }
  let(:received_at) { Time.zone.parse('2026-11-03 10:00') }
  before do
    lead
    lead.update_columns(admin_user_id: owner.id)
    lead.activities.create!(kind: 'distributed', metadata: {admin_user_id: owner.id}, created_at: received_at)
  end

  def result
    described_class.new(tenant: tenant, leads: [lead], starts_at: Time.zone.parse('2026-11-02'), ends_at: Time.zone.parse('2026-11-08').end_of_day).call.fetch(lead.id)
  end

  it 'separa recebimento de primeiro contato e ignora aceite, anotações e robô' do
    lead.activities.create!(kind: 'accepted', metadata: {admin_user_id: owner.id}, created_at: received_at + 1.minute)
    lead.activities.create!(kind: 'note', metadata: {admin_user_id: owner.id, body: 'Interno'}, created_at: received_at + 2.minutes)
    lead.activities.create!(kind: 'whatsapp_out', source_category: 'automation', metadata: {admin_user_id: owner.id}, created_at: received_at + 3.minutes)
    lead.activities.create!(kind: 'note', metadata: {admin_user_id: owner.id, contact_kind: 'ligacao'}, created_at: received_at + 4.minutes)
    expect(result).to include(received_at: received_at, first_attended_at: received_at + 4.minutes, visits: 0, pool: false)
  end

  it 'não atribui atendimento antigo ou de outro corretor ao responsável atual' do
    lead.activities.create!(kind: 'whatsapp_out', metadata: {admin_user_id: owner.id}, created_at: received_at - 1.day)
    lead.activities.create!(kind: 'whatsapp_out', metadata: {admin_user_id: previous.id}, created_at: received_at + 1.minute)
    expect(result[:first_attended_at]).to be_nil
  end

  it 'conta somente visitas realizadas no período pelo corretor atual' do
    create(:appointment, tenant: tenant, lead: lead, admin_user: owner, kind: 'visita', status: 'realizado', starts_at: received_at + 1.day)
    create(:appointment, tenant: tenant, lead: lead, admin_user: owner, kind: 'visita', status: 'agendado', starts_at: received_at + 2.days)
    create(:appointment, tenant: tenant, lead: lead, admin_user: owner, kind: 'visita', status: 'cancelado', starts_at: received_at + 3.days)
    create(:appointment, tenant: tenant, lead: lead, admin_user: owner, kind: 'reuniao', status: 'realizado', starts_at: received_at + 1.day)
    create(:appointment, tenant: tenant, lead: lead, admin_user: owner, kind: 'visita', status: 'realizado', starts_at: received_at + 1.month)
    expect(result[:visits]).to eq(1)
  end

  it 'reconhece captura do bolsão sem trocar a origem original' do
    lead.update_columns(origin: 'Instagram Direct')
    lead.activities.create!(kind: 'accepted', metadata: {admin_user_id: owner.id, shark_tank: true}, created_at: received_at + 1.day)
    expect(result).to include(pool: true, received_at: received_at + 1.day)
    expect(lead.reload.origin).to eq('Instagram Direct')
  end

  it 'usa auditoria de transferência e mantém desconhecido o que não foi registrado' do
    lead.activities.delete_all
    expect(result).to include(received_at: nil, first_attended_at: nil)
    LeadAuditLog.create!(tenant: tenant, lead: lead, action: 'assigned', source: 'admin', changeset: {admin_user_id: {before: previous.id, after: owner.id}}, created_at: received_at)
    expect(result[:received_at]).to eq(received_at)
  end

  it 'rejeita dados fora da conta' do
    other = Tenant.create!(name: 'Outra', slug: "report-facts-#{SecureRandom.hex(3)}")
    expect { described_class.new(tenant: other, leads: [lead]).call }.to raise_error(ArgumentError)
  end
  it 'usa mensagens humanas enviadas no Instagram e ignora respostas automáticas' do
    lead.instagram_messages.create!(message_id: 'auto', direction: 'outbound', body: 'Seu nome?', occurred_at: received_at + 1.minute)
    lead.instagram_messages.create!(message_id: 'human', direction: 'outbound', body: 'Olá!', occurred_at: received_at + 5.minutes, sent_by_admin_user: owner)
    expect(result[:first_attended_at]).to eq(received_at + 5.minutes)
  end

  it 'usa WhatsApp efetivamente enviado, sem contar mensagem pendente' do
    conversation = tenant.whatsapp_conversations.create!(lead: lead, contact_phone: '5547998887777')
    conversation.messages.create!(direction: 'outbound', status: 'pending', msg_type: 'text', admin_user: owner, body: 'Rascunho', created_at: received_at + 1.minute)
    conversation.messages.create!(direction: 'outbound', status: 'sent', msg_type: 'text', admin_user: owner, body: 'Olá', sent_at: received_at + 10.minutes)
    expect(result[:first_attended_at]).to eq(received_at + 10.minutes)
  end

end
