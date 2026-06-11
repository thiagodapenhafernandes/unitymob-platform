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
    broker_profile = Profile.create!(name: "Corretor filtro #{SecureRandom.hex(4)}", permissions: Profile.default_permissions_for("Corretor"))
    manager_profile = Profile.create!(name: "Gerente filtro #{SecureRandom.hex(4)}", permissions: Profile.default_permissions_for("Gerente"))
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

  it "records allowed administrative page access" do
    sign_in admin

    expect {
      get admin_access_security_path
    }.to change { AccessAuditLog.where(event_type: "admin_access", result: "allowed", admin_user: admin).count }.by(1)

    log = AccessAuditLog.recent.first
    expect(log.path).to eq(admin_access_security_path)
    expect(log.reason).to eq("Acesso administrativo permitido")
  end
end
