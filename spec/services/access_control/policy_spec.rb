require "rails_helper"

RSpec.describe AccessControl::Policy do
  let(:request) { instance_double(ActionDispatch::Request, remote_ip: "10.0.0.10") }

  it "denies login when IP is blocked for the user" do
    user = create(:admin_user, email: "policy-#{SecureRandom.hex(8)}@salute.test")
    create(:access_control_rule, rule_type: "block_ip", scope_type: "user", admin_user: user, ip_value: "10.0.0.10")

    result = described_class.call(admin_user: user, request: request)

    expect(result).not_to be_allowed
    expect(result.reason).to eq("IP bloqueado para login administrativo")
  end

  it "denies broker login outside allowlist when global enforcement is enabled" do
    user = create(:admin_user, email: "policy-#{SecureRandom.hex(8)}@salute.test")
    allow(AccessControl::Settings).to receive(:broker_ip_allowlist_enabled?).and_return(true)
    create(:access_control_rule, rule_type: "allow_ip", scope_type: "global", ip_value: "10.0.0.20")

    result = described_class.call(admin_user: user, request: request)

    expect(result).not_to be_allowed
    expect(result.reason).to eq("IP fora da lista permitida para este usuário")
  end

  it "allows broker login when IP matches allowlist" do
    user = create(:admin_user, email: "policy-#{SecureRandom.hex(8)}@salute.test")
    allow(AccessControl::Settings).to receive(:broker_ip_allowlist_enabled?).and_return(true)
    create(:access_control_rule, rule_type: "allow_ip", scope_type: "global", ip_value: "10.0.0.0/24")

    result = described_class.call(admin_user: user, request: request)

    expect(result).to be_allowed
  end
end
