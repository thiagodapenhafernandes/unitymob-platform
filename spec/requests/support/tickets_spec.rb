require 'rails_helper'
RSpec.describe 'Chamados na conta', type: :request do
  include Devise::Test::IntegrationHelpers
  let(:tenant) { Tenant.create!(name: 'Conta suporte', slug: "support-#{SecureRandom.hex(5)}") }
  let(:user) { create(:admin_user, tenant: tenant, profile: tenant.profiles.create!(name: 'Atendimento', axis: 'vertical', permissions: { 'dashboard' => { 'view' => true } })) }
  let!(:account) { Support::Account.create!(uid: SecureRandom.uuid, local_tenant_id: tenant.id, name: tenant.name, endpoint: 'https://admin.unitymob.com.br', secret: 's' * 64) }
  before { host! 'localhost'; sign_in user }
  def ticket_for(requester = user)
    account.tickets.create!(subject: 'Erro no imóvel', requester_id: requester.id.to_s, requester_name: requester.name, intake: Support::Ticket::QUESTIONS.keys.index_with { 'Detalhes' })
  end
  def csrf
    get '/admin/support/tickets/new'
    Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')&.[]('content')
  end
  it 'cria com contexto local e fila persistida, sem aceitar autor enviado no formulário' do
    token = csrf
    expect(response).to have_http_status(:ok)
    post '/admin/support/tickets', params: { authenticity_token: token, support_ticket: { subject: 'Não consigo salvar', requester_id: '999', intake: Support::Ticket::QUESTIONS.keys.index_with { 'Detalhes' } } }
    expect(response).to have_http_status(:redirect)
    ticket = account.tickets.last
    expect(ticket.requester_id).to eq(user.id.to_s)
    expect(ticket.deliveries.count).to eq(1)
    get "/admin/support/tickets/#{ticket.id}"
    expect(response.body).to include('Envio pendente')
  end
  it 'não lê chamado de outro solicitante nem altera o estado' do
    other = create(:admin_user, tenant: tenant)
    ticket = ticket_for(other)
    get "/admin/support/tickets/#{ticket.id}"
    expect(response).to have_http_status(:not_found)
    patch "/admin/support/tickets/#{ticket_for.id}", params: { authenticity_token: csrf, support_ticket: { status: 'resolvido' } }
    expect(response).to have_http_status(:forbidden)
  end
  it 'proprietário consulta chamados da própria conta' do
    ticket = ticket_for
    sign_in create(:admin_user, :admin, tenant: tenant)
    get "/admin/support/tickets/#{ticket.id}"
    expect(response).to have_http_status(:ok)
  end
  it 'usuário sem permissão específica acessa suporte; conta desativada continua bloqueada' do
    sign_in create(:admin_user, tenant: tenant)
    get '/admin/support/tickets'
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css('[data-support-new-url]')).to be_present
    account.update!(active: false)
    get '/admin/support/tickets'
    expect(response).to have_http_status(:forbidden)
  end

  it 'impersonação permite abrir como o usuário representado sem acessar conversas alheias' do
    other_ticket = ticket_for(create(:admin_user, tenant: tenant))
    system_admin = create(:admin_user, super_admin: true)
    sign_out :admin_user
    sign_in system_admin, scope: :admin_user
    get admin_system_users_path
    expect(response).to have_http_status(:ok)
    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')&.[]('content')
    post admin_system_user_impersonation_path(user), params: { authenticity_token: token }
    expect(session[:impersonator_admin_user_id]).to eq(system_admin.id)
    token = csrf
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css('[data-support-new-url]')).to be_present
    post '/admin/support/tickets?modal=1', params: { authenticity_token: token, support_ticket: { subject: 'Usuário impersonado', intake: Support::Ticket::QUESTIONS.keys.index_with { 'Detalhes' } } }
    expect(response).to have_http_status(:created)
    expect(account.tickets.last.requester_id).to eq(user.id.to_s)
    get "/admin/support/tickets/#{other_ticket.id}"
    expect(response).to have_http_status(:not_found)
  end
  it 'isola contas mesmo quando o solicitante tem o mesmo ID no payload' do
    other = Support::Account.create!(uid: SecureRandom.uuid, local_tenant_id: tenant.id + 1000, name: 'Outra', endpoint: 'https://admin.unitymob.com.br', secret: 'x' * 64)
    ticket = other.tickets.create!(subject: 'Privado', requester_id: user.id.to_s, requester_name: user.name, intake: Support::Ticket::QUESTIONS.keys.index_with { 'Detalhes' })
    get "/admin/support/tickets/#{ticket.id}"
    expect(response).to have_http_status(:not_found)
  end
  it 'abre o formulário em modal no menu e confirma sem tirar o usuário da página' do
    get '/admin/support/tickets/new', params: { modal: '1' }
    expect(response.body).to include('id="support_modal_form"')
    post '/admin/support/tickets?modal=1', params: { authenticity_token: csrf, support_ticket: { subject: 'Modal', intake: Support::Ticket::QUESTIONS.keys.index_with { 'Detalhes' } } }
    expect(response).to have_http_status(:created)
    expect(response.body).to include('data-support-created', 'Você pode continuar trabalhando')
    get '/admin/support/tickets'
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('.ax-navbar__user [data-support-new-url]')).to be_present
    expect(document.at_css('#support-modal [role="dialog"]')).to be_present
    get '/admin/support/tickets/new'
    document = Nokogiri::HTML(response.body)
    expect(document.css('#support_modal_form').count).to eq(1)
    expect(document.at_css('#support_form')['target']).to eq('_top')
  end

  it 'omite chamados finalizados da lista e dos avisos do usuário' do
    own = ticket_for
    other = ticket_for(create(:admin_user, tenant: tenant))
    other.messages.create!(side: 'support', author: 'Suporte', body: 'Outra conversa')
    own.update!(status: 'resolvido', resolved_at: Time.current)
    get '/admin/support/updates', headers: { 'ACCEPT' => 'application/json' }
    expect(response.parsed_body).to include('count' => 0, 'ticket_id' => nil)
    get '/admin/support/tickets'
    expect(Nokogiri::HTML(response.body).at_css(%(a[data-support-ticket-link][href="/admin/support/tickets/#{own.id}"]))).to be_nil
    expect(response.body).not_to include('<option value="resolvido">')
    get "/admin/support/tickets/#{own.id}"
    get '/admin/support/updates', headers: { 'ACCEPT' => 'application/json' }
    expect(response.parsed_body).to include('count' => 0, 'open_count' => 0)
  end

  it 'conta respostas pessoais por chamado e atualiza após leitura' do
    own = ticket_for
    2.times { own.messages.create!(side: 'support', author: 'Suporte', body: 'Resposta') }
    ticket_for(create(:admin_user, tenant: tenant)).messages.create!(side: 'support', author: 'Suporte', body: 'Outra pessoa')
    get '/admin/support/updates', headers: { 'ACCEPT' => 'application/json' }
    expect(response.parsed_body['count']).to eq(1)
    get '/admin/support/tickets'
    badges = Nokogiri::HTML(response.body).css('[data-support-unread-count]')
    expect(badges.size).to eq(2)
    expect(badges.map(&:text)).to eq(['1', '1'])
    expect(badges.any? { |b| b.key?('hidden') }).to be(false)
    get "/admin/support/tickets/#{own.id}"
    get '/admin/support/updates', headers: { 'ACCEPT' => 'application/json' }
    expect(response.parsed_body['count']).to eq(0)
    get '/admin/support/tickets'
    expect(Nokogiri::HTML(response.body).css('[data-support-unread-count][hidden]').size).to eq(2)
  end

  it 'usa header compacto compartilhado no detalhe sem perder conversa e resposta' do
    ticket = ticket_for
    get "/admin/support/tickets/#{ticket.id}"
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    header = document.at_css('.ax-mobile-detail-header')
    expect(header.at_css('a')['href']).to eq('/admin/support/tickets')
    expect(header.at_css('.ax-mobile-detail-header__title').text).to include('Chamado', ticket.subject)
    expect(header.at_css('.ax-mobile-detail-header__status').text).to eq('Aberto')
    expect(document.at_css('#reply')).to be_present
    expect(document.at_css('.ax-conversation')).to be_present
  end

  it 'oferece somente telas do menu autorizado e exige descrição em Outro' do
    get '/admin/support/tickets/new', params: { modal: '1' }
    document = Nokogiri::HTML(response.body)
    screens = document.css('#choice_menu_module option').map(&:text)
    expect(screens).to include('Outro')
    expect(screens).not_to include('Usuários', 'Saúde do sistema', 'Integrações')
    expect(document.css('[data-support-choice] select').size).to eq(5)
    expect(document.css('[data-support-choice] select').all? { |select| select.css('option[value="other"]').one? }).to be(true)
    choices = Support::Intake::OPTIONS.transform_values(&:first).merge('menu_module' => 'other')
    post '/admin/support/tickets?modal=1', params: { authenticity_token: csrf, intake_choices: choices, support_ticket: {source_path: '/admin'} }
    expect(response).to have_http_status(:unprocessable_entity)
    post '/admin/support/tickets?modal=1', params: { authenticity_token: csrf, intake_choices: choices, intake_details: {'menu_module' => 'Minha tela'}, support_ticket: { source_path: '/admin?token=privado' } }
    expect(response).to have_http_status(:created)
    ticket = account.tickets.last
    expect(ticket.intake['menu_module']).to eq('Minha tela')
    expect(ticket.subject).to include('Minha tela')
    expect(ticket.diagnostics['page_url']).not_to include('token')
  end

  it 'não aceita uma tela fora das opções autorizadas e não mistura erros de outras pessoas' do
    choices = Support::Intake::OPTIONS.transform_values(&:first).merge('menu_module' => 'Admin secreto')
    post '/admin/support/tickets?modal=1', params: { authenticity_token: csrf, intake_choices: choices, support_ticket: { source_path: '/admin' } }
    expect(response).to have_http_status(:unprocessable_entity)
    own = ErrorEvent.record!(RuntimeError.new('qa-own-error'), source: 'request', context: {tenant_id: tenant.id, admin_user_id: user.id})
    ErrorEvent.record!(RuntimeError.new('qa-other-error'), source: 'request', context: {tenant_id: tenant.id, admin_user_id: user.id + 9999})
    choices['menu_module'] = 'other'
    post '/admin/support/tickets?modal=1', params: { authenticity_token: csrf, intake_choices: choices, intake_details: {'menu_module'=>'Uma tela'}, support_ticket: {source_path:'/admin'} }
    expect(response).to have_http_status(:created)
    expect(account.tickets.last.diagnostics['recent_errors'].map { |e| e['id'] }).to eq([own.id])
    expect(account.tickets.last.diagnostics.to_json).not_to include('qa-own-error', 'qa-other-error')
  end

end
