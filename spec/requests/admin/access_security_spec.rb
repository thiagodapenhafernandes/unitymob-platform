require "rails_helper"

RSpec.describe "Admin::AccessSecurity", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "access-security-#{SecureRandom.hex(8)}@salute.test") }

  around do |example|
    previous_tenant = Current.tenant
    Current.tenant = admin.tenant
    example.run
  ensure
    Current.tenant = previous_tenant
  end

  before do
    host! "localhost"
    sign_in admin
  end

  it "renders the access security page and creates IP rules" do
    get admin_access_security_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Segurança de Acesso")
    expect(response.body).to include("Configurações")
    expect(response.body).to include("Regras de IP")
    expect(response.body).to include("Aparelhos")
    expect(response.body).to include("Limpar")

    post admin_access_control_rules_path, params: {
      access_control_rule: {
        name: "Loja Centro",
        rule_type: "allow_ip",
        scope_type: "global",
        ip_value: "10.0.0.0/24",
        enabled: "1"
      }
    }

    expect(response).to redirect_to(admin_access_security_path)
    expect(AccessControlRule.last.name).to eq("Loja Centro")
    expect(AccessControlRule.last.tenant).to eq(admin.tenant)
  end

  it "approves trusted devices" do
    device = create(:trusted_device, admin_user: admin)

    patch admin_trusted_device_path(device, status: "trusted")

    expect(response).to redirect_to(admin_access_security_path(anchor: "devices"))
    expect(device.reload.status).to eq("trusted")
  end

  it "filtra regras de IP e aparelhos por perfil, usuário e status" do
    broker_profile = Profile.create!(name: "Perfil device #{SecureRandom.hex(4)}", position: 8_900, permissions: Profile.default_permissions_for("Corretor"))
    other_profile = Profile.create!(name: "Outro device #{SecureRandom.hex(4)}", position: 700, permissions: Profile.default_permissions_for("Gerente"))
    broker = create(:admin_user, profile: broker_profile, name: "Usuário Device Certo")
    other = create(:admin_user, profile: other_profile, name: "Usuário Device Errado")

    create(:access_control_rule, name: "Regra Perfil Certo", scope_type: "profile", profile: broker_profile, rule_type: "allow_ip", ip_value: "10.10.0.0/24")
    create(:access_control_rule, name: "Regra Usuário Errado", scope_type: "user", admin_user: other, rule_type: "block_ip", ip_value: "10.20.0.0/24")
    create(:trusted_device, admin_user: broker, status: "pending", last_ip: "10.10.0.5", browser: "Chrome", device_type: "Computador")
    create(:trusted_device, admin_user: other, status: "blocked", last_ip: "10.20.0.5", browser: "Safari", device_type: "Celular")

    get admin_access_security_path, params: {
      rule_type: "allow_ip",
      scope_type: "profile",
      rule_profile_id: broker_profile.id,
      rule_ip: "10.10"
    }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Regra Perfil Certo")
    expect(response.body).not_to include("Regra Usuário Errado")

    get admin_access_security_path, params: {
      device_status: "pending",
      device_profile_id: broker_profile.id,
      device_admin_user_id: broker.id,
      device_ip: "10.10.0.5",
      device_browser: "Chrome",
      device_type: "Computador"
    }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Usuário Device Certo")
    expect(response.body).not_to include("10.20.0.5")
  end

  it "não exibe regras nem aparelhos confiáveis de outro Tenant" do
    other_tenant = Tenant.create!(name: "Outro segurança #{SecureRandom.hex(3)}", slug: "outro-seguranca-#{SecureRandom.hex(3)}")
    other_profile = other_tenant.profiles.find_by!(key: "agent")
    other_user = create(:admin_user, tenant: other_tenant, profile: other_profile, name: "Usuário Segurança Outro")
    create(:access_control_rule, tenant: admin.tenant, name: "Regra Tenant Atual", rule_type: "allow_ip", ip_value: "10.30.0.0/24")
    create(:access_control_rule, tenant: other_tenant, name: "Regra Outro Tenant", rule_type: "allow_ip", ip_value: "10.40.0.0/24")
    create(:trusted_device, tenant: admin.tenant, admin_user: admin, last_ip: "10.30.0.5")
    create(:trusted_device, tenant: other_tenant, admin_user: other_user, last_ip: "10.40.0.5")

    get admin_access_security_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Regra Tenant Atual")
    expect(response.body).not_to include("Regra Outro Tenant")
    expect(response.body).to include("10.30.0.5")
    expect(response.body).not_to include("10.40.0.5")
  end

  it "não permite aprovar aparelho confiável de outro Tenant" do
    other_tenant = Tenant.create!(name: "Outro device #{SecureRandom.hex(3)}", slug: "outro-device-#{SecureRandom.hex(3)}")
    other_profile = other_tenant.profiles.find_by!(key: "agent")
    other_user = create(:admin_user, tenant: other_tenant, profile: other_profile)
    other_device = create(:trusted_device, tenant: other_tenant, admin_user: other_user, status: "pending")

    patch admin_trusted_device_path(other_device, status: "trusted")

    expect(response).to have_http_status(:not_found)
    expect(other_device.reload.status).to eq("pending")
  end

  it "limita segurança de acesso à subárvore do perfil vertical intermediário" do
    tenant = admin.tenant
    manager_profile = Profile.create!(
      tenant: tenant,
      name: "Gestor Segurança #{SecureRandom.hex(4)}",
      axis: "vertical",
      position: 700,
      permissions: {
        "dashboard" => { "view" => true },
        "access_security" => { "manage" => true, "scope" => "team" }
      }
    )
    agent_profile = tenant.profiles.find_by!(key: "agent")
    manager = create(:admin_user, tenant: tenant, profile: manager_profile, manager: admin, name: "Gestor Segurança")
    subordinate = create(:admin_user, tenant: tenant, profile: agent_profile, manager: manager, name: "Subordinado Segurança")
    peer = create(:admin_user, tenant: tenant, profile: agent_profile, manager: admin, name: "Par Segurança")

    create(:access_control_rule, tenant: tenant, name: "Regra global fora do gestor", scope_type: "global", rule_type: "allow_ip", ip_value: "10.70.0.0/24")
    create(:access_control_rule, tenant: tenant, name: "Regra perfil fora do gestor", scope_type: "profile", profile: agent_profile, rule_type: "allow_ip", ip_value: "10.71.0.0/24")
    create(:access_control_rule, tenant: tenant, name: "Regra subordinado visível", scope_type: "user", admin_user: subordinate, rule_type: "allow_ip", ip_value: "10.72.0.0/24")
    create(:access_control_rule, tenant: tenant, name: "Regra par invisível", scope_type: "user", admin_user: peer, rule_type: "allow_ip", ip_value: "10.73.0.0/24")
    create(:trusted_device, tenant: tenant, admin_user: subordinate, last_ip: "10.72.0.5", status: "pending")
    create(:trusted_device, tenant: tenant, admin_user: peer, last_ip: "10.73.0.5", status: "pending")

    sign_in manager

    get admin_access_security_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Regra subordinado visível")
    expect(response.body).to include("10.72.0.5")
    expect(response.body).not_to include("Regra global fora do gestor")
    expect(response.body).not_to include("Regra perfil fora do gestor")
    expect(response.body).not_to include("Regra par invisível")
    expect(response.body).not_to include("10.73.0.5")
    expect(response.body).to include("value=\"user\"")
    expect(response.body).not_to include("value=\"global\"")
    expect(response.body).not_to include("value=\"profile\"")
    expect(response.body).not_to include(">Configurações<")
    expect(response.body).not_to include("Salvar configurações")
  end

  it "impede perfil intermediário de criar regra global e de alterar regra ou aparelho fora da subárvore" do
    tenant = admin.tenant
    manager_profile = Profile.create!(
      tenant: tenant,
      name: "Gestor Segurança Restrita #{SecureRandom.hex(4)}",
      axis: "vertical",
      position: 710,
      permissions: {
        "dashboard" => { "view" => true },
        "access_security" => { "manage" => true, "scope" => "team" }
      }
    )
    agent_profile = tenant.profiles.find_by!(key: "agent")
    manager = create(:admin_user, tenant: tenant, profile: manager_profile, manager: admin)
    subordinate = create(:admin_user, tenant: tenant, profile: agent_profile, manager: manager)
    peer = create(:admin_user, tenant: tenant, profile: agent_profile, manager: admin)
    peer_rule = create(:access_control_rule, tenant: tenant, name: "Regra peer", scope_type: "user", admin_user: peer, rule_type: "allow_ip", ip_value: "10.80.0.0/24", enabled: true)
    peer_device = create(:trusted_device, tenant: tenant, admin_user: peer, status: "pending")

    sign_in manager

    expect {
      post admin_access_control_rules_path, params: {
        access_control_rule: {
          name: "Regra global recusada",
          rule_type: "allow_ip",
          scope_type: "global",
          admin_user_id: "",
          ip_value: "10.81.0.0/24",
          enabled: "1"
        }
      }
    }.not_to change(AccessControlRule, :count)

    expect(response).to redirect_to(admin_access_security_path)

    expect {
      post admin_access_control_rules_path, params: {
        access_control_rule: {
          name: "Regra subordinado aceita",
          rule_type: "allow_ip",
          scope_type: "global",
          admin_user_id: subordinate.id,
          ip_value: "10.82.0.0/24",
          enabled: "1"
        }
      }
    }.to change(AccessControlRule, :count).by(1)

    expect(AccessControlRule.last).to have_attributes(scope_type: "user", admin_user_id: subordinate.id)

    patch admin_access_control_rule_path(peer_rule), params: { access_control_rule: { enabled: "false" } }
    expect(response).to have_http_status(:not_found)
    expect(peer_rule.reload.enabled).to be(true)

    patch admin_trusted_device_path(peer_device, status: "trusted")
    expect(response).to have_http_status(:not_found)
    expect(peer_device.reload.status).to eq("pending")
  end

  it "impede perfil intermediário de alterar configurações globais de segurança" do
    tenant = admin.tenant
    manager_profile = Profile.create!(
      tenant: tenant,
      name: "Gestor Segurança Global #{SecureRandom.hex(4)}",
      axis: "vertical",
      position: 720,
      permissions: {
        "dashboard" => { "view" => true },
        "access_security" => { "manage" => true, "scope" => "team" }
      }
    )
    manager = create(:admin_user, tenant: tenant, profile: manager_profile, manager: admin)
    Setting.set(AccessControl::Settings::ENFORCE_BROKER_IP_KEY, "false", "baseline")
    Setting.set(AccessControl::Settings::ENFORCE_BROKER_DEVICE_KEY, "false", "baseline")

    sign_in manager

    patch admin_access_security_path, params: {
      enforce_broker_ip_allowlist: "1",
      enforce_broker_trusted_devices: "1"
    }

    expect(response).to redirect_to(admin_access_security_path(anchor: "rules-pane"))
    expect(flash[:alert]).to match(/Dono da conta/i)
    expect(AccessControl::Settings.broker_ip_allowlist_enabled?).to be(false)
    expect(AccessControl::Settings.broker_trusted_devices_enabled?).to be(false)
  end
end
