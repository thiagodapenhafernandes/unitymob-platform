require 'rails_helper'

RSpec.describe 'Contador de não lidos da aba', type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let(:lead) { create(:lead, tenant: admin.tenant, admin_user: admin) }
  before { host! 'localhost'; sign_in admin }

  it 'envia invalidação pelo contrato posicional do Action Cable' do
    payloads = []
    allow(ActionCable.server).to receive(:broadcast) do |*args, **options|
      raise ArgumentError unless args.length == 2 && options.empty?
      payloads << args
    end
    InAppNotification.invalidate_title!(admin.tenant_id)
    expect(payloads).to eq([["unread_title:#{admin.tenant_id}", { event: "unread_changed" }]])
  end

  it 'soma avisos, Direct e WhatsApp sem contar outra conta ou saída' do
    InAppNotification.notify!(admin_user: admin, kind: 'notice', title: 'Aviso')
    message = lead.instagram_messages.create!(message_id: 'title-in', body: 'Privado', occurred_at: Time.current)
    lead.instagram_messages.create!(message_id: 'title-out', direction: 'outbound', occurred_at: Time.current)
    conversation = WhatsappConversation.create!(tenant: admin.tenant, assigned_admin_user: admin, contact_phone: '5547999990077', unread_count: 3)
    incoming = conversation.messages.create!(tenant: admin.tenant, direction: 'inbound', msg_type: 'text', body: 'Privado')
    InAppNotification.notify_whatsapp_message!(conversation, incoming)
    other = create(:admin_user, :admin)
    InAppNotification.notify!(admin_user: other, kind: 'notice', title: 'Outra conta')
    get summary_admin_in_app_notifications_path
    expect(response.parsed_body).to include('total' => 3, 'unread_count' => 3)
    expect(response.parsed_body['html']).to include('bi-whatsapp', 'WhatsApp', 'bi-bell', 'Sistema', 'Privado')
    post read_direct_admin_in_app_notifications_path, params: { lead_id: lead.id, cursor: message.id }
    expect(response).to have_http_status(:no_content)
    get summary_admin_in_app_notifications_path
    expect(response.parsed_body['total']).to eq(2)
  end

  it 'não marca mensagem que chegou após o cursor exibido nem avisos' do
    first = lead.instagram_messages.create!(message_id: 'first', occurred_at: Time.current)
    lead.instagram_messages.create!(message_id: 'later', occurred_at: Time.current)
    post read_direct_admin_in_app_notifications_path, params: { lead_id: lead.id, cursor: first.id }
    expect(InAppNotification.unread.where(admin_user: admin, kind: 'instagram_message').count).to eq(1)
  end

  it 'mantém sino e título pessoais mesmo para gestores com acesso a todos' do
    observer = create(:admin_user, :admin, tenant: admin.tenant)
    lead.instagram_messages.create!(message_id: 'owner-only', occurred_at: Time.current)
    expect(InAppNotification.where(admin_user: observer, kind: 'instagram_message')).to be_empty
    get summary_admin_in_app_notifications_path
    expect(response.parsed_body['html']).to include('Instagram Direct', lead.display_name, 'bi-instagram')
    expect(response.parsed_body['total']).to eq(response.parsed_body['unread_count'])
  end

  it 'renderiza remetente e preview escapados, inclusive em avisos legados' do
    message = lead.instagram_messages.create!(message_id: 'preview-safe', body: '<script>privado</script>', occurred_at: Time.current)
    notice = InAppNotification.find_by!(admin_user: admin, kind: 'instagram_message')
    notice.update_columns(body: nil, metadata: { lead_id: lead.id, instagram_message_id: message.id })
    get summary_admin_in_app_notifications_path
    html = response.parsed_body['html']
    expect(html).to include('bi-instagram', 'Instagram Direct', lead.display_name, '&lt;script&gt;privado&lt;/script&gt;', 'Não lida')
    expect(html).not_to include('<script>')
  end

  it 'não recupera preview de mensagem referenciada de outra conta' do
    foreign = create(:lead, tenant: Tenant.create!(name: 'Outra conta', slug: "preview-other-#{SecureRandom.hex(5)}"))
    message = foreign.instagram_messages.create!(message_id: 'foreign-preview', body: 'SEGREDO OUTRA CONTA', occurred_at: Time.current)
    InAppNotification.create!(admin_user: admin, tenant: admin.tenant, kind: 'instagram_message', title: 'Mensagem',
      metadata: { lead_id: lead.id, instagram_message_id: message.id })
    get summary_admin_in_app_notifications_path
    expect(response.parsed_body['html']).not_to include('SEGREDO OUTRA CONTA')
  end

  it 'pagina notificações sem incluir itens de outro usuário' do
    31.times { InAppNotification.create!(admin_user: admin, tenant: admin.tenant, kind: 'notice', title: 'Aviso pessoal') }
    get summary_admin_in_app_notifications_path
    cursor = response.parsed_body['next_cursor']
    expect(response.parsed_body['html'].scan('data-notification-id=').length).to eq(30)
    get summary_admin_in_app_notifications_path, params: { before: cursor }
    expect(response.parsed_body['html'].scan('data-notification-id=').length).to eq(1)
    expect(response.parsed_body['next_cursor']).to be_nil
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
