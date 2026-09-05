require 'rails_helper'
RSpec.describe 'Acesso assistido', type: :request do
  let(:tenant) { Tenant.create!(name: 'Conta assistida', slug: "assist-#{SecureRandom.hex(5)}") }
  let(:user) { create(:admin_user, :admin, tenant: tenant) }
  let(:account) { Support::Account.create!(uid: SecureRandom.uuid, local_tenant_id: tenant.id, name: tenant.name, endpoint: 'https://admin.unitymob.com.br', secret: 's' * 64) }
  let(:ticket) { account.tickets.create!(subject: 'Ajuda', requester_id: user.id.to_s, requester_name: user.name, intake: Support::Ticket::QUESTIONS.keys.index_with { 'Detalhes' }) }
  before { host! 'localhost' }
  def grant
    body = { ticket_uid: ticket.uid, operator_id: '7', operator_name: 'Ana' }.to_json
    stamp = Time.current.to_i.to_s
    post '/internal/support/v1/access', params: body, headers: { 'CONTENT_TYPE' => 'application/json', 'X-Support-Account' => account.uid, 'X-Support-Timestamp' => stamp, 'X-Support-Signature' => Support::Transport.signature(account.secret, stamp, body) }
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body).fetch('token')
  end
  it 'entra sem consentimento, registra operador e bloqueia segurança e exportação' do
    token = grant
    post '/support/access', params: { token: token }
    expect(response).to redirect_to('/admin')
    expect(Support::AccessSession.last).to be_live
    get '/admin'
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('body > .ax-support-access').text).to include('Ana')
    expect(html.at_css('body')['class']).not_to include('<aside')
    get '/admin/profiles'
    expect(response).to have_http_status(:forbidden)
    get '/admin/habitations/print'
    expect(response).to have_http_status(:forbidden)
    expect(Support::Audit.where(action: 'access_denied').count).to eq(2)
  end
  it 'rejeita replay e sessão expirada' do
    token = grant
    post '/support/access', params: { token: token }
    Support::AccessSession.last.update!(expires_at: 1.second.ago)
    get '/admin'
    expect(response).to redirect_to('/admin/sign_in')
    post '/support/access', params: { token: token }
    expect(response).to have_http_status(:gone)
  end
  it 'rejeita credencial vencida antes de abrir sessão' do
    token = grant
    Support::AccessSession.last.update!(redeem_before: 1.second.ago)
    post '/support/access', params: { token: token }
    expect(response).to have_http_status(:gone)
  end
  it 'permite ações externas escolhidas, mas nega novas ações sem classificação' do
    expect(Support::AssistedPolicy.allowed?('admin/whatsapp_inbox', 'send_message')).to be(true)
    expect(Support::AssistedPolicy.allowed?('admin/whatsapp_campaigns', 'start')).to be(true)
    expect(Support::AssistedPolicy.allowed?('admin/automation_workflows', 'publish')).to be(true)
    expect(Support::AssistedPolicy.allowed?('admin/leads', 'attend')).to be(true)
    expect(Support::AssistedPolicy.allowed?('admin/leads', 'destroy')).to be(false)
    expect(Support::AssistedPolicy.allowed?('admin/leads', 'future_action')).to be(false)
    expect(Support::AssistedPolicy.allowed?('admin/whatsapp_integration', 'show')).to be(false)
  end
end
