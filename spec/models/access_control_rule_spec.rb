require "rails_helper"

RSpec.describe AccessControlRule, type: :model do
  it "matches single IPs and CIDR ranges" do
    expect(build(:access_control_rule, ip_value: "10.0.0.1")).to be_matches_ip("10.0.0.1")
    expect(build(:access_control_rule, ip_value: "10.0.0.0/24")).to be_matches_ip("10.0.0.88")
  end

  it "requires target when scope is user or profile" do
    user_rule = build(:access_control_rule, scope_type: "user")
    profile_rule = build(:access_control_rule, scope_type: "profile")

    expect(user_rule).not_to be_valid
    expect(profile_rule).not_to be_valid
  end

  it "não permite alvo de perfil ou usuário de outro Tenant" do
    tenant = Tenant.create!(name: "Tenant #{SecureRandom.hex(3)}", slug: "tenant-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro #{SecureRandom.hex(3)}", slug: "outro-#{SecureRandom.hex(3)}")
    other_profile = other_tenant.profiles.find_by!(key: "agent")
    other_user = create(:admin_user, tenant: other_tenant, profile: other_profile)

    profile_rule = build(:access_control_rule, tenant: tenant, scope_type: "profile", profile: other_profile)
    user_rule = build(:access_control_rule, tenant: tenant, scope_type: "user", admin_user: other_user)

    expect(profile_rule).not_to be_valid
    expect(profile_rule.errors[:profile]).to be_present
    expect(user_rule).not_to be_valid
    expect(user_rule.errors[:admin_user]).to be_present
  end

  it "infere o Tenant a partir do perfil alvo" do
    tenant = Tenant.create!(name: "Tenant #{SecureRandom.hex(3)}", slug: "tenant-#{SecureRandom.hex(3)}")
    profile = tenant.profiles.find_by!(key: "agent")
    rule = build(:access_control_rule, scope_type: "profile", profile: profile)

    expect(rule).to be_valid
    expect(rule.tenant).to eq(tenant)
  end
end
