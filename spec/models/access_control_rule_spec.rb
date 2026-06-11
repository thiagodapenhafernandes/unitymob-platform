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
end
