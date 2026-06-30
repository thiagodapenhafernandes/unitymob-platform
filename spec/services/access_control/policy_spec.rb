require "rails_helper"

RSpec.describe AccessControl::Policy do
  it "ignora regras globais de IP de outro Tenant" do
    tenant = Tenant.create!(name: "Tenant #{SecureRandom.hex(3)}", slug: "tenant-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro #{SecureRandom.hex(3)}", slug: "outro-#{SecureRandom.hex(3)}")
    profile = tenant.profiles.find_by!(key: "agent")
    user = create(:admin_user, tenant: tenant, profile: profile)
    create(:access_control_rule, tenant: other_tenant, rule_type: "block_ip", scope_type: "global", ip_value: "10.90.0.5")
    request = instance_double(ActionDispatch::Request, remote_ip: "10.90.0.5")

    result = described_class.call(admin_user: user, request: request)

    expect(result).to be_allowed
  end

  it "não trata Admin do Sistema como corretor nas regras globais de broker" do
    Setting.set(AccessControl::Settings::ENFORCE_BROKER_IP_KEY, "true", "Teste")
    system_admin = create(:admin_user, super_admin: true)
    request = instance_double(ActionDispatch::Request, remote_ip: "10.90.0.5")

    result = described_class.call(admin_user: system_admin, request: request)

    expect(result).to be_allowed
  end
end
