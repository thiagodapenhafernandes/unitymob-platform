require "rails_helper"

RSpec.describe "Admin::System", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

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
    }.to change { AccessAuditLog.where(event_type: "admin_access", result: "allowed", admin_user: sys).count }.by(1)

    expect(response).to have_http_status(:ok)
    expect(AccessAuditLog.where(event_type: "admin_access", result: "allowed", admin_user: sys).last.tenant_id).to be_nil
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

  it "permite admin do sistema impersonar o dono da conta pelo painel do sistema" do
    sys = create(:admin_user, super_admin: true)
    tenant = Tenant.create!(name: "Tenant sistema #{SecureRandom.hex(3)}", slug: "tenant-sistema-#{SecureRandom.hex(3)}")
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    owner = create(:admin_user, :admin, tenant: tenant, profile: owner_profile, name: "Dono da Conta")
    sign_in sys, scope: :admin_user

    post admin_system_tenant_owner_impersonation_path(tenant)

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

    post admin_system_user_impersonation_path(user)

    expect(response).to redirect_to(admin_root_path)
    expect(request.session[:impersonator_admin_user_id]).to eq(sys.id)
    expect(AccessAuditLog.where(event_type: "impersonation_start", admin_user: user)).to exist
  end
end
