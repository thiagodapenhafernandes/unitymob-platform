require "rails_helper"

RSpec.describe "Admin::System", type: :request do
  include Devise::Test::IntegrationHelpers

  before do
    host! "localhost"
    Tenants::LocalPublicHostOverride.clear!
  end

  after do
    Tenants::LocalPublicHostOverride.clear!
  end

  let(:profile_admin) { Tenant.default.profiles.find_by!(key: "tenant_owner") }

  it "redireciona usuário não autenticado" do
    get admin_system_path
    expect(response).to have_http_status(:redirect)
  end

  it "bloqueia admin da conta que NÃO é admin do sistema" do
    account_admin = create(:admin_user, profile: profile_admin, super_admin: false)
    sign_in account_admin, scope: :admin_user

    get admin_system_path
    expect(response).to redirect_to(admin_root_path)
    expect(flash[:alert]).to match(/Admin do Sistema/i)
  end

  it "permite acesso ao admin do sistema" do
    sys = create(:admin_user, super_admin: true)
    sign_in sys, scope: :admin_user

    expect {
      get admin_system_path
    }.to change { AccessAuditLog.where(event_type: "sensitive_access", result: "allowed", admin_user: sys).count }.by(1)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-system-login-release-field", "ax-table__col--w-120")
    expect(response.body).to include("Gestão de contas", "Abrir contas", "Operadores globais com acesso")
    system_workspace = Nokogiri::HTML(response.body).at_css(".ax-system").to_html
    expect(system_workspace).not_to match(/\bstyle\s*=/i)
    expect(AccessAuditLog.where(event_type: "sensitive_access", result: "allowed", admin_user: sys).last.tenant_id).to be_nil
  end

  it "lista contas em menu dedicado com filtros e ações" do
    sys = create(:admin_user, super_admin: true)
    tenant = Tenant.create!(name: "Conta Menu #{SecureRandom.hex(3)}", slug: "conta-menu-#{SecureRandom.hex(3)}")
    inactive = Tenant.create!(name: "Conta Arquivada #{SecureRandom.hex(3)}", slug: "conta-arquivada-#{SecureRandom.hex(3)}", active: false)
    owner = create(:admin_user, :admin, tenant: tenant, profile: tenant.profiles.find_by!(key: "tenant_owner"), name: "Dono Menu")
    sign_in sys, scope: :admin_user

    get admin_system_tenants_path, params: { q: "Conta Menu", status: "active" }

    table_text = Nokogiri::HTML(response.body).css("table.ax-table tbody").text

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Contas cadastradas na plataforma", "Nova conta")
    expect(response.body).to include(admin_system_tenant_path(tenant), edit_admin_system_tenant_path(tenant))
    expect(table_text).to include(tenant.name, owner.name)
    expect(table_text).not_to include(inactive.name)
  end

  it "ativa uma conta para o host local de desenvolvimento" do
    sys = create(:admin_user, super_admin: true)
    tenant = Tenant.create!(name: "Conexão Imobiliária", slug: "conexao-imobiliaria-#{SecureRandom.hex(3)}")
    sign_in sys, scope: :admin_user

    get admin_system_tenants_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Usar no dev")

    patch activate_dev_host_admin_system_tenant_path(tenant), params: csrf_params_from_response

    expect(response).to redirect_to(admin_system_tenants_path)
    expect(Tenants::LocalPublicHostOverride.tenant).to eq(tenant)
    expect(flash[:notice]).to include("https://dev.unitymob.com.br/")
    expect(AccessAuditLog.where(event_type: "tenant_dev_host_activated", admin_user: sys)).to exist

    follow_redirect!
    expect(response.body).to include("dev: #{tenant.name}", "em uso no dev")
  end

  it "renderiza formulário de nova conta para admin do sistema" do
    sys = create(:admin_user, super_admin: true)
    sign_in sys, scope: :admin_user

    get new_admin_system_tenant_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Nova conta", "Dono da conta", "tenant_provisioning_form_owner_email")
    expect(response.body).not_to match(/\bstyle\s*=/i)
  end

  it "cria tenant ativo com perfis e dono da conta pela interface do sistema" do
    sys = create(:admin_user, super_admin: true)
    tenant_slug = "conexao-imobiliaria-#{SecureRandom.hex(3)}"
    sign_in sys, scope: :admin_user

    get new_admin_system_tenant_path

    expect {
      post admin_system_tenants_path,
           params: csrf_params_from_response.merge(
             tenant_provisioning_form: {
               tenant_name: "Conexão Imobiliária",
               tenant_slug: tenant_slug,
               primary_domain_hostname: "https://www.conexao.test:443/",
               primary_domain_ssl_mode: "shared_wildcard",
               primary_domain_notes: "Wildcard configurado fora do Rails",
               owner_name: "Dona Conexão",
               owner_email: "dona@conexao.test",
               owner_phone: "(47) 99999-0000",
               owner_password: "password123",
               owner_password_confirmation: "password123"
             }
           )
    }.to change(Tenant, :count).by(1)
      .and change(AdminUser.account_members, :count).by(1)

    tenant = Tenant.find_by!(slug: tenant_slug)

    expect(response).to redirect_to(admin_system_tenant_path(tenant))
    expect(flash[:notice]).to include("Conexão Imobiliária", "Dona Conexão")

    owner = tenant.admin_users.find_by!(email: "dona@conexao.test")
    domain = tenant.tenant_domains.find_by!(hostname: "www.conexao.test")

    expect(tenant).to be_active
    expect(domain).to be_primary_domain
    expect(domain).to be_active
    expect(domain.ssl_mode).to eq("shared_wildcard")
    expect(tenant.profiles.find_by!(key: "tenant_owner")).to be_present
    expect(tenant.profiles.find_by!(key: "agent")).to be_present
    expect(owner).to be_active
    expect(owner).to be_tenant_owner
    expect(owner).not_to be_system_admin
    expect(AccessAuditLog.where(event_type: "tenant_provisioned", admin_user: sys)).to exist
  end

  it "não cria tenant quando os dados do dono da conta são inválidos" do
    sys = create(:admin_user, super_admin: true)
    existing_user = create(:admin_user, email: "existente@empresa.test")
    sign_in sys, scope: :admin_user

    get new_admin_system_tenant_path

    expect {
      post admin_system_tenants_path,
           params: csrf_params_from_response.merge(
             tenant_provisioning_form: {
               tenant_name: "Conta Inválida",
               tenant_slug: "conta-invalida",
               owner_name: "Dono Inválido",
               owner_email: existing_user.email,
               owner_password: "password123",
               owner_password_confirmation: "password123"
             }
           )
    }.not_to change(Tenant, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("E-mail de acesso já está em uso")
    expect(Tenant.find_by(slug: "conta-invalida")).to be_nil
  end

  it "permite visualizar, editar, inativar e reativar uma conta" do
    sys = create(:admin_user, super_admin: true)
    tenant = Tenant.create!(name: "Conta CRUD #{SecureRandom.hex(3)}", slug: "conta-crud-#{SecureRandom.hex(3)}")
    owner = create(:admin_user, :admin, tenant: tenant, profile: tenant.profiles.find_by!(key: "tenant_owner"), name: "Dono CRUD")
    sign_in sys, scope: :admin_user

    get admin_system_tenant_path(tenant)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(tenant.name, owner.name, "Editar conta")
    expect(response.body).not_to include("Inativar conta", "tenant_public_site_theme", "Adicionar domínio")

    get edit_admin_system_tenant_path(tenant)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Editar conta", "tenant_name", "Identidade visual resolvida", "Salvar alterações")
    expect(response.body).not_to include("tenant_public_site_theme", "Salvar tema", "Salvar conta")

    patch admin_system_tenant_path(tenant),
          params: csrf_params_from_response.merge(tenant: { name: "Conta CRUD Editada", slug: "conta-crud-editada", active: "1" })

    expect(response).to redirect_to(admin_system_tenant_path(tenant))
    expect(tenant.reload.name).to eq("Conta CRUD Editada")
    expect(tenant.slug).to eq("conta-crud-editada")
    expect(AccessAuditLog.where(event_type: "tenant_updated", admin_user: sys)).to exist

    get edit_admin_system_tenant_path(tenant)
    patch inactivate_admin_system_tenant_path(tenant), params: csrf_params_from_response

    expect(response).to redirect_to(admin_system_tenant_path(tenant))
    expect(tenant.reload).not_to be_active
    expect(AccessAuditLog.where(event_type: "tenant_inactivated", admin_user: sys)).to exist

    get edit_admin_system_tenant_path(tenant)
    patch reactivate_admin_system_tenant_path(tenant), params: csrf_params_from_response

    expect(response).to redirect_to(admin_system_tenant_path(tenant))
    expect(tenant.reload).to be_active
    expect(AccessAuditLog.where(event_type: "tenant_reactivated", admin_user: sys)).to exist
  end

  it "permite gerenciar domínios da conta no admin do sistema" do
    sys = create(:admin_user, super_admin: true)
    tenant = Tenant.create!(name: "Conta Domínios #{SecureRandom.hex(3)}", slug: "conta-dominios-#{SecureRandom.hex(3)}")
    sign_in sys, scope: :admin_user

    get edit_admin_system_tenant_path(tenant)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Domínios da conta", "sem emissão automática de SSL", "Adicionar domínio")

    expect {
      post admin_system_tenant_domains_path(tenant),
           params: csrf_params_from_response.merge(
             tenant_domain: {
               hostname: "https://www.tenant.test/site",
               ssl_mode: "external_certificate",
               notes: "Certificado externo"
             }
           )
    }.to change { tenant.tenant_domains.count }.by(1)

    domain = tenant.tenant_domains.find_by!(hostname: "www.tenant.test")
    expect(response).to redirect_to(edit_admin_system_tenant_path(tenant))
    expect(domain.ssl_mode).to eq("external_certificate")
    expect(AccessAuditLog.where(event_type: "tenant_domain_created", admin_user: sys)).to exist

    get edit_admin_system_tenant_path(tenant)
    patch admin_system_tenant_domain_path(tenant, domain),
          params: csrf_params_from_response.merge(
            tenant_domain: {
              hostname: "site.tenant.test",
              ssl_mode: "shared_wildcard",
              notes: "Wildcard no proxy",
              active: "0",
              primary_domain: "1"
            }
          )

    expect(response).to redirect_to(edit_admin_system_tenant_path(tenant))
    expect(domain.reload).to have_attributes(hostname: "site.tenant.test", ssl_mode: "shared_wildcard", active: true, primary_domain: true)
    expect(AccessAuditLog.where(event_type: "tenant_domain_updated", admin_user: sys)).to exist

    get edit_admin_system_tenant_path(tenant)
    delete admin_system_tenant_domain_path(tenant, domain), params: csrf_params_from_response

    expect(response).to redirect_to(edit_admin_system_tenant_path(tenant))
    expect(tenant.tenant_domains.where(id: domain.id)).not_to exist
    expect(AccessAuditLog.where(event_type: "tenant_domain_destroyed", admin_user: sys)).to exist
  end

  it "resolve o css do site implicitamente ao editar a identidade da conta" do
    sys = create(:admin_user, super_admin: true)
    tenant = Tenant.create!(name: "Conta Tema #{SecureRandom.hex(3)}", slug: "conta-tema-#{SecureRandom.hex(3)}")
    sign_in sys, scope: :admin_user

    get admin_system_tenant_path(tenant)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Identidade visual resolvida", "Alterar no editor", "Salute Imóveis")
    expect(response.body).not_to include("tenant_public_site_theme", "Salvar tema", "Salvar conta")

    get edit_admin_system_tenant_path(tenant)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Identidade visual resolvida", "Salvar alterações", "public_site_themes/saluteimoveis.css")
    expect(response.body).not_to include("tenant_public_site_theme", "Salvar tema", "Salvar conta")

    patch admin_system_tenant_path(tenant),
          params: csrf_params_from_response.merge(tenant: {
            name: "Conexão Imobiliária",
            slug: "conta-tema-editada-#{SecureRandom.hex(3)}",
            active: "1",
            public_site_theme: "saluteimoveis"
          })

    expect(response).to redirect_to(admin_system_tenant_path(tenant))
    expect(tenant.reload.public_site_theme_key).to eq("conexaoimobiliaria")
    expect(tenant.public_site_theme).to eq("saluteimoveis")
    expect(tenant.public_site_stylesheet).to eq("public_site_themes/conexaoimobiliaria")
    expect(AccessAuditLog.where(event_type: "tenant_updated", admin_user: sys)).to exist
  end

  it "bloqueia admin da conta no formulário de nova conta" do
    account_admin = create(:admin_user, profile: profile_admin, super_admin: false)
    sign_in account_admin, scope: :admin_user

    get new_admin_system_tenant_path
    expect(response).to redirect_to(admin_root_path)

    get admin_root_path
    post admin_system_tenants_path,
         params: csrf_params_from_response.merge(
           tenant_provisioning_form: {
             tenant_name: "Conta Bloqueada",
             owner_name: "Dono",
             owner_email: "dono@bloqueada.test",
             owner_password: "password123",
             owner_password_confirmation: "password123"
           }
         )
    expect(response).to redirect_to(admin_root_path)
    expect(Tenant.find_by(slug: "conta-bloqueada")).to be_nil
  end

  it "permite ao admin do sistema liberar o rate limit de login com auditoria" do
    sys = create(:admin_user, super_admin: true)
    user = create(:admin_user, email: "bloqueado@salute.test")
    sign_in sys, scope: :admin_user

    expect(Security::LoginRateLimit).to receive(:reset!).with(admin_user: user)
      .and_return(Security::LoginRateLimit::Result.new(email: user.email, ips: ["203.0.113.10"]))

    get admin_system_path
    post admin_system_login_rate_limit_reset_path,
         params: csrf_params_from_response.merge(login_rate_limit: { email: user.email })

    expect(response).to redirect_to(admin_system_path)
    expect(flash[:notice]).to include(user.email)
    log = AccessAuditLog.where(event_type: "rate_limit_reset", admin_user: user).last
    expect(log).to be_present
    expect(log.metadata).to include("system_admin_id" => sys.id, "released_ips" => ["203.0.113.10"])
  end

  it "não permite que admin da conta libere rate limit de login" do
    account_admin = create(:admin_user, profile: profile_admin, super_admin: false)
    sign_in account_admin, scope: :admin_user

    get admin_root_path
    post admin_system_login_rate_limit_reset_path,
         params: csrf_params_from_response.merge(login_rate_limit: { email: account_admin.email })

    expect(response).to redirect_to(admin_root_path)
    expect(AccessAuditLog.where(event_type: "rate_limit_reset")).not_to exist
  end

  it "lista usuários para impersonação com filtros de status, tipo e conta" do
    sys = create(:admin_user, super_admin: true, name: "Admin Sistema")
    tenant = Tenant.create!(name: "Tenant filtros #{SecureRandom.hex(3)}", slug: "tenant-filtros-#{SecureRandom.hex(3)}")
    agent_profile = tenant.profiles.find_by!(key: "agent")
    active_user = create(:admin_user, tenant: tenant, profile: agent_profile, name: "Ativo Visível", active: true)
    inactive_user = create(:admin_user, tenant: tenant, profile: agent_profile, name: "Inativo Oculto", active: false)
    other_user = create(:admin_user, name: "Outra Conta")
    sign_in sys, scope: :admin_user

    get admin_system_users_path, params: { tenant_id: tenant.id, status: "active", user_kind: "account" }

    table_text = Nokogiri::HTML(response.body).css("table.ax-table tbody").text

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("system_user_hierarchy_filter")
    expect(response.body).to include('data-controller="auto-submit admin-user-access"')
    expect(response.body).to include('data-controller="tom-select"')
    expect(response.body).to include("hierarchical-user-filter:change->auto-submit#submit")
    expect(response.body).to include('class="ax-num ax-table__col--w-130"')
    expect(response.body).to include("Usuários globais disponíveis para impersonação auditada")
    expect(table_text).to include(active_user.name)
    expect(table_text).not_to include(inactive_user.name)
    expect(table_text).not_to include(other_user.name)
  end

  it "lista admins do sistema separadamente dos usuários da conta" do
    sys = create(:admin_user, super_admin: true, name: "Admin Sistema")
    account_user = create(:admin_user, name: "Usuário de Conta")
    sign_in sys, scope: :admin_user

    get admin_system_users_path, params: { user_kind: "system" }

    table_text = Nokogiri::HTML(response.body).css("table.ax-table tbody").text

    expect(response).to have_http_status(:ok)
    expect(table_text).to include(sys.name)
    expect(table_text).not_to include(account_user.name)
  end

  it "filtra a listagem global por perfil vertical, função horizontal e hierarquia da conta" do
    sys = create(:admin_user, super_admin: true)
    tenant = Tenant.create!(name: "Tenant hierarquia #{SecureRandom.hex(3)}", slug: "tenant-hierarquia-#{SecureRandom.hex(3)}")
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    agent_profile = tenant.profiles.find_by!(key: "agent")
    manager_profile = Profile.create!(
      tenant: tenant,
      name: "Gerente Base #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 600,
      permissions: { "corretores" => { "view" => true } }
    )
    horizontal = Profile.create!(
      tenant: tenant,
      name: "Vendas Alto Padrão #{SecureRandom.hex(3)}",
      axis: "horizontal",
      vertical_profile: agent_profile,
      permissions: { "leads" => { "view" => true, "scope" => "own" } }
    )
    owner = create(:admin_user, :admin, tenant: tenant, profile: owner_profile, name: "Dono Hierarquia")
    manager = create(:admin_user, tenant: tenant, profile: manager_profile, manager: owner, name: "Gestor Filtro")
    broker = create(:admin_user, tenant: tenant, profile: agent_profile, horizontal_profile: horizontal, manager: manager, name: "Corretor Filtrado")
    peer = create(:admin_user, tenant: tenant, profile: agent_profile, horizontal_profile: horizontal, manager: owner, name: "Corretor Fora")
    sign_in sys, scope: :admin_user

    get admin_system_users_path,
        params: {
          tenant_id: tenant.id,
          profile_id: agent_profile.id,
          horizontal_profile_id: horizontal.id,
          hierarchy_user_id: manager.id,
          user_kind: "account"
        }

    table_text = Nokogiri::HTML(response.body).css("table.ax-table tbody").text

    expect(response).to have_http_status(:ok)
    expect(table_text).to include(broker.name)
    expect(table_text).not_to include(manager.name)
    expect(table_text).not_to include(peer.name)
    expect(response.body).to include(%(data-vertical-profile-id="#{agent_profile.id}"))
  end

  it "mantém admin do sistema fora de áreas operacionais" do
    sys = create(:admin_user, super_admin: true)
    sign_in sys, scope: :admin_user

    get admin_root_path

    expect(response).to redirect_to(admin_system_path)
    expect(flash[:alert]).to match(/impersonação/i)
  end

  it "não permite admin do sistema acessar área operacional selecionando Tenant por parâmetro" do
    sys = create(:admin_user, super_admin: true)
    tenant = Tenant.create!(name: "Tenant sistema #{SecureRandom.hex(3)}", slug: "tenant-sistema-#{SecureRandom.hex(3)}")
    sign_in sys, scope: :admin_user

    get admin_root_path, params: { tenant_id: tenant.id }

    expect(response).to redirect_to(admin_system_path)
    expect(request.session[:admin_current_tenant_id]).to be_nil

    get admin_root_path
    expect(response).to redirect_to(admin_system_path)
  end

  it "permite admin do sistema impersonar o dono da conta pelo menu de contas" do
    sys = create(:admin_user, super_admin: true)
    tenant = Tenant.create!(name: "Tenant sistema #{SecureRandom.hex(3)}", slug: "tenant-sistema-#{SecureRandom.hex(3)}")
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    owner = create(:admin_user, :admin, tenant: tenant, profile: owner_profile, name: "Dono da Conta")
    sign_in sys, scope: :admin_user

    path = admin_system_tenant_owner_impersonation_path(tenant)
    get admin_system_tenants_path
    form = form_for_action(path)

    expect(form["data-turbo"]).to eq("false")

    post path, params: csrf_params_from_response

    expect(response).to redirect_to(admin_root_path)
    expect(request.session[:impersonator_admin_user_id]).to eq(sys.id)
    expect(AccessAuditLog.where(event_type: "impersonation_start", admin_user: owner)).to exist

    follow_redirect!

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Dono da Conta")
  end

  it "permite admin do sistema impersonar qualquer usuário pela listagem global" do
    sys = create(:admin_user, super_admin: true)
    tenant = Tenant.create!(name: "Tenant user impersonation #{SecureRandom.hex(3)}", slug: "tenant-user-impersonation-#{SecureRandom.hex(3)}")
    agent_profile = tenant.profiles.find_by!(key: "agent")
    user = create(:admin_user, tenant: tenant, profile: agent_profile, name: "Usuário Impersonado")
    sign_in sys, scope: :admin_user

    path = admin_system_user_impersonation_path(user)
    get admin_system_users_path, params: { q: user.email }
    form = form_for_action(path)

    expect(form["data-turbo"]).to eq("false")

    post path, params: csrf_params_from_response

    expect(response).to redirect_to(admin_root_path)
    expect(request.session[:impersonator_admin_user_id]).to eq(sys.id)
    expect(AccessAuditLog.where(event_type: "impersonation_start", admin_user: user)).to exist
  end

  def csrf_params_from_response
    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')&.[]("content")
    token.present? ? { authenticity_token: token } : {}
  end

  def form_for_action(path)
    form = Nokogiri::HTML(response.body).at_css(%(form[action="#{path}"]))
    expect(form).to be_present
    expect(form.at_css('input[name="authenticity_token"]')).to be_present if ActionController::Base.allow_forgery_protection
    form
  end
end
