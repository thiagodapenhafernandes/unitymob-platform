require "rails_helper"

RSpec.describe "Admin::AccessAuditLogs", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "access-audit-#{SecureRandom.hex(8)}@salute.test") }

  before do
    host! "localhost"
  end

  it "records successful and failed login attempts" do
    expect {
      post admin_user_session_path, params: {
        admin_user: { email: admin.email, password: "password123" }
      }, headers: { "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh) Safari/605.1.15" }
    }.to change(AccessAuditLog, :count).by(1)

    expect(AccessAuditLog.last).to have_attributes(event_type: "login", result: "allowed", admin_user_id: admin.id)

    delete destroy_admin_user_session_path

    expect {
      post admin_user_session_path, params: {
        admin_user: { email: admin.email, password: "senha-errada" }
      }
    }.to change(AccessAuditLog, :count).by(1)

    expect(AccessAuditLog.last).to have_attributes(event_type: "login", result: "denied", reason: "Senha inválida")
  end

  it "envia perfil intermediário com dashboard para o admin após login" do
    profile = Profile.create!(
      tenant: admin.tenant,
      name: "Coordenador Login #{SecureRandom.hex(4)}",
      axis: "vertical",
      position: 600,
      permissions: {
        "dashboard" => { "view" => true },
        "leads" => { "view" => true, "scope" => "team" }
      }
    )
    coordinator = create(:admin_user, tenant: admin.tenant, profile: profile, email: "coordenador-login-#{SecureRandom.hex(4)}@example.test")

    post admin_user_session_path, params: {
      admin_user: { email: coordinator.email, password: "password123" }
    }

    expect(response).to redirect_to(admin_root_path)
  end

  it "envia usuário desktop sem dashboard para o workspace administrativo após login" do
    profile = Profile.create!(
      tenant: admin.tenant,
      name: "Operador Campo #{SecureRandom.hex(4)}",
      axis: "vertical",
      position: 800,
      permissions: {}
    )
    field_user = create(:admin_user, tenant: admin.tenant, profile: profile, email: "campo-login-#{SecureRandom.hex(4)}@example.test")

    post admin_user_session_path, params: {
      admin_user: { email: field_user.email, password: "password123" }
    }

    expect(response).to redirect_to(admin_root_path)
  end

  it "envia usuário mobile para o PWA de campo após login" do
    profile = Profile.create!(
      tenant: admin.tenant,
      name: "Operador Mobile #{SecureRandom.hex(4)}",
      axis: "vertical",
      position: 801,
      permissions: {}
    )
    field_user = create(:admin_user, tenant: admin.tenant, profile: profile, email: "mobile-login-#{SecureRandom.hex(4)}@example.test")

    post admin_user_session_path,
         params: { admin_user: { email: field_user.email, password: "password123" } },
         headers: { "User-Agent" => "Mozilla/5.0 (Linux; Android 15) Mobile" }

    expect(response).to redirect_to(field_root_path)
  end

  it "renders access audit page and menu entry" do
    create(:access_audit_log, admin_user: admin, result: "denied", reason: "Senha inválida")
    sign_in admin

    get admin_access_audit_logs_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Auditoria de Acessos")
    expect(response.body).to include("Senha inválida")
    expect(response.body).to include("IPs únicos")
    expect(response.body).to include("Limpar")
  end

  it "filtra auditoria por perfil, usuário, dispositivo e rota" do
    broker_profile = Profile.create!(tenant: admin.tenant, name: "Corretor filtro #{SecureRandom.hex(4)}", axis: "vertical", position: 8_900, permissions: Profile.default_permissions_for("Corretor"))
    manager_profile = Profile.create!(tenant: admin.tenant, name: "Gerente filtro #{SecureRandom.hex(4)}", axis: "vertical", position: 700, permissions: Profile.default_permissions_for("Gerente"))
    broker = create(:admin_user, profile: broker_profile, name: "Broker Auditado")
    manager = create(:admin_user, profile: manager_profile, name: "Manager Auditado")
    broker_log = create(:access_audit_log, admin_user: broker, event_type: "access_denied", result: "denied", device_type: "Celular", browser: "Chrome", controller_name: "admin/leads", action_name: "index", path: "/admin/leads?status=novo")
    create(:access_audit_log, admin_user: manager, event_type: "login", result: "allowed", reason: "Motivo que não deve aparecer", device_type: "Computador", browser: "Safari", controller_name: "admin/habitations", action_name: "index", path: "/admin/habitations")

    sign_in admin

    get admin_access_audit_logs_path, params: {
      profile_id: broker_profile.id,
      admin_user_id: broker.id,
      device_type: "Celular",
      browser: "Chrome",
      access_controller: "admin/leads",
      access_action: "index",
      path: "/admin/leads"
    }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(broker_log.reason)
    expect(response.body).to include("Broker Auditado")
    expect(response.body).not_to include("Motivo que não deve aparecer")
    expect(response.body).to include("/admin/leads")
    expect(response.body).to include("status=novo")
  end

  it "não exibe logs de acesso de outro Tenant" do
    other_tenant = Tenant.create!(name: "Outro audit #{SecureRandom.hex(3)}", slug: "outro-audit-#{SecureRandom.hex(3)}")
    other_profile = other_tenant.profiles.find_by!(key: "agent")
    other_user = create(:admin_user, tenant: other_tenant, profile: other_profile, name: "Usuário Outro Tenant")
    create(:access_audit_log, admin_user: admin, reason: "Log tenant atual", path: "/admin/atual")
    create(:access_audit_log, admin_user: other_user, reason: "Log outro tenant", path: "/admin/outro")

    sign_in admin

    get admin_access_audit_logs_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Log tenant atual")
    expect(response.body).not_to include("Log outro tenant")
  end

  it "limita auditoria de acessos à subárvore do perfil vertical intermediário" do
    tenant = admin.tenant
    owner = admin
    manager_profile = Profile.create!(
      tenant: tenant,
      name: "Gestor Auditoria Acesso #{SecureRandom.hex(4)}",
      axis: "vertical",
      position: 700,
      permissions: {
        "dashboard" => { "view" => true },
        "access_audit" => { "view" => true, "scope" => "team" }
      }
    )
    agent_profile = tenant.profiles.find_by!(key: "agent")
    manager = create(:admin_user, tenant: tenant, profile: manager_profile, manager: owner, name: "Gestor Auditoria")
    subordinate = create(:admin_user, tenant: tenant, profile: agent_profile, manager: manager, name: "Subordinado Auditável")
    peer = create(:admin_user, tenant: tenant, profile: agent_profile, manager: owner, name: "Par Fora da Árvore")

    create(:access_audit_log, admin_user: manager, reason: "Log do gestor")
    create(:access_audit_log, admin_user: subordinate, reason: "Log do subordinado")
    create(:access_audit_log, admin_user: peer, reason: "Log do par fora")
    create(:access_audit_log, admin_user: owner, reason: "Log do dono acima")

    sign_in manager

    get admin_access_audit_logs_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Log do gestor")
    expect(response.body).to include("Log do subordinado")
    expect(response.body).not_to include("Log do par fora")
    expect(response.body).not_to include("Log do dono acima")
    expect(response.body).not_to include("Par Fora da Árvore")
  end

  it "registra acesso permitido somente em área administrativa sensível" do
    sign_in admin

    expect {
      get admin_access_security_path
    }.to change { AccessAuditLog.where(event_type: "sensitive_access", result: "allowed", admin_user: admin).count }.by(1)

    log = AccessAuditLog.recent.first
    expect(log.path).to eq(admin_access_security_path)
    expect(log.reason).to eq("Acesso permitido a área sensível")
  end

  it "não registra navegação administrativa comum" do
    sign_in admin

    expect {
      get admin_root_path
    }.not_to change(AccessAuditLog, :count)
  end

  it "não registra navegação permitida no Field" do
    field_user = create(:admin_user, tenant: admin.tenant, profile: admin.tenant.profiles.find_by!(key: "agent"))
    sign_in field_user

    expect {
      get field_root_path
    }.not_to change(AccessAuditLog, :count)
  end

  it "oculta acessos administrativos legados na visão padrão e permite filtrá-los" do
    legacy = create(:access_audit_log, admin_user: admin, event_type: "admin_access", reason: "Ruído legado")
    relevant = create(:access_audit_log, admin_user: admin, event_type: "login", reason: "Evento relevante")
    sign_in admin

    get admin_access_audit_logs_path

    expect(response.body).to include(relevant.reason)
    expect(response.body).not_to include(legacy.reason)

    get admin_access_audit_logs_path(event_type: "admin_access")

    expect(response.body).to include(legacy.reason)
  end
end
