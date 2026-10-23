require 'rails_helper'

RSpec.describe 'Contador de não lidos da aba', type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let(:lead) { create(:lead, tenant: admin.tenant, admin_user: admin) }
  before { host! 'localhost'; sign_in admin }

  it 'soma avisos, Direct e WhatsApp sem contar outra conta ou saída' do
    InAppNotification.notify!(admin_user: admin, kind: 'notice', title: 'Aviso')
    message = lead.instagram_messages.create!(message_id: 'title-in', body: 'Privado', occurred_at: Time.current)
    lead.instagram_messages.create!(message_id: 'title-out', direction: 'outbound', occurred_at: Time.current)
    WhatsappConversation.create!(tenant: admin.tenant, contact_phone: '5547999990077', unread_count: 3)
    other = create(:admin_user, :admin)
    InAppNotification.notify!(admin_user: other, kind: 'notice', title: 'Outra conta')
    get summary_admin_in_app_notifications_path
    expect(response.parsed_body).to include('total' => 5, 'unread_count' => 2)
    post read_direct_admin_in_app_notifications_path, params: { lead_id: lead.id, cursor: message.id }
    expect(response).to have_http_status(:no_content)
    get summary_admin_in_app_notifications_path
    expect(response.parsed_body['total']).to eq(4)
  end

  it 'não marca mensagem que chegou após o cursor exibido nem avisos' do
    first = lead.instagram_messages.create!(message_id: 'first', occurred_at: Time.current)
    lead.instagram_messages.create!(message_id: 'later', occurred_at: Time.current)
    post read_direct_admin_in_app_notifications_path, params: { lead_id: lead.id, cursor: first.id }
    expect(InAppNotification.unread.where(admin_user: admin, kind: 'instagram_message').count).to eq(1)
  end

  it 'nega acesso a outro tenant e conta apenas conversas permitidas' do
    profile = admin.tenant.profiles.create!(name: 'Próprios', axis: 'vertical', position: 700,
      permissions: { 'leads' => { 'view' => true, 'scope' => 'own' }, 'whatsapp_inbox' => { 'view' => true, 'scope' => 'own' } })
    agent = create(:admin_user, tenant: admin.tenant, profile: profile)
    lead.instagram_messages.create!(message_id: 'private', occurred_at: Time.current)
    WhatsappConversation.create!(tenant: admin.tenant, assigned_admin_user: admin, contact_phone: '5547999990077', unread_count: 3)
    sign_out admin; sign_in agent
    get summary_admin_in_app_notifications_path
    expect(response.parsed_body['total']).to eq(0)
    foreign = create(:lead)
    post read_direct_admin_in_app_notifications_path, params: { lead_id: foreign.id, cursor: 9999 }
    expect(response).to have_http_status(:not_found)
    expect(InAppNotification.where(admin_user: agent, kind: 'instagram_message')).to be_empty
  end
end
