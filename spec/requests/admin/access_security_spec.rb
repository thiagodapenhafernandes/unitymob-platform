require "rails_helper"

RSpec.describe "Admin::AccessSecurity", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "access-security-#{SecureRandom.hex(8)}@salute.test") }

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
  end

  it "approves trusted devices" do
    device = create(:trusted_device, admin_user: admin)

    patch admin_trusted_device_path(device, status: "trusted")

    expect(response).to redirect_to(admin_access_security_path(anchor: "devices"))
    expect(device.reload.status).to eq("trusted")
  end

  it "filtra regras de IP e aparelhos por perfil, usuário e status" do
    broker_profile = Profile.create!(name: "Perfil device #{SecureRandom.hex(4)}", permissions: Profile.default_permissions_for("Corretor"))
    other_profile = Profile.create!(name: "Outro device #{SecureRandom.hex(4)}", permissions: Profile.default_permissions_for("Gerente"))
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
end
