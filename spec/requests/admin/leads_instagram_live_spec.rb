require 'rails_helper'

RSpec.describe 'Instagram Direct sem recarregar o lead', type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let(:lead) { create(:lead, tenant: admin.tenant, admin_user: admin, instagram_account_id: '555', instagram_scoped_id: '777') }
  before do
    host! 'localhost'
    sign_in admin
    lead.instagram_messages.create!(message_id: 'incoming', body: 'Mensagem recebida', occurred_at: 1.hour.ago)
  end

  it 'envia por Turbo e atualiza somente mensagens/status, sem substituir o composer' do
    allow(Instagram::Reply).to receive(:call) do
      lead.instagram_messages.create!(message_id: 'outgoing', body: 'Resposta', direction: 'outbound', occurred_at: Time.current, sent_by_admin_user: admin)
    end
    post reply_instagram_admin_lead_path(lead), params: { body: 'Resposta' }, as: :turbo_stream
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('turbo-stream', "lead_instagram_messages_#{lead.id}", 'Resposta')
    expect(response.body).not_to include('<textarea', '<form', 'action="refresh"')
  end

  it 'mantém o formulário intacto e mostra erro sem redirecionar' do
    allow(Instagram::Reply).to receive(:call).and_raise(Instagram::Reply::Error, 'Janela de 24h encerrada.')
    post reply_instagram_admin_lead_path(lead), params: { body: 'Rascunho' }, as: :turbo_stream
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include('24h', "lead_instagram_status_#{lead.id}")
    expect(response.body).not_to include('<textarea', '<form')
  end

  it 'o GET de atualização contém só o frame de leitura, escapando mensagens' do
    lead.instagram_messages.create!(message_id: 'unsafe', body: '<script>alert(1)</script>', occurred_at: Time.current)
    get instagram_thread_admin_lead_path(lead)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('<turbo-frame', '&lt;script&gt;')
    expect(response.body).not_to include('<textarea', '<script>', '<html')
  end

  it 'recusa outra conta no GET e no envio' do
    foreign = create(:lead, tenant: Tenant.create!(name: "Outra", slug: "ig-other-#{SecureRandom.hex(5)}"))
    get instagram_thread_admin_lead_path(foreign)
    expect(response).to have_http_status(:not_found)
  end

  it 'recusa envio Turbo para outra conta' do
    foreign = create(:lead, tenant: Tenant.create!(name: 'Outra', slug: "ig-post-#{SecureRandom.hex(5)}"))
    allow(Instagram::Reply).to receive(:call)
    post reply_instagram_admin_lead_path(foreign), params: { body: 'Não enviar' }, as: :turbo_stream
    expect(response).to have_http_status(:not_found)
    expect(Instagram::Reply).not_to have_received(:call)
  end

  it 'revalida o dono no GET e no POST Turbo após transferência' do
    profile = admin.tenant.profiles.create!(name: 'Chat próprio', axis: 'vertical', position: 700,
      permissions: { 'leads' => { 'view' => true, 'edit' => true, 'scope' => 'own' } })
    agent = create(:admin_user, tenant: admin.tenant, profile: profile)
    sign_out admin
    sign_in agent
    allow(Instagram::Reply).to receive(:call)
    get instagram_thread_admin_lead_path(lead)
    expect(response).to redirect_to(admin_leads_path)
    post reply_instagram_admin_lead_path(lead), params: { body: 'Não enviar' }, as: :turbo_stream
    expect(response).to have_http_status(:forbidden)
    expect(Instagram::Reply).not_to have_received(:call)
  end
end
