require "rails_helper"

RSpec.describe Leads::StickyAssignment do
  let(:tenant) { Tenant.create!(name: "Tenant sticky #{SecureRandom.hex(3)}", slug: "tenant-sticky-#{SecureRandom.hex(3)}") }
  let(:other_tenant) { Tenant.create!(name: "Outro sticky #{SecureRandom.hex(3)}", slug: "outro-sticky-#{SecureRandom.hex(3)}") }

  it "não reaproveita corretor de lead anterior de outro tenant" do
    setting = LeadSetting.instance
    setting.update!(
      stickiness_enabled: true,
      stickiness_match: "phone",
      stickiness_owner: "any_assignment",
      stickiness_fallback: "active_any",
      stickiness_window_days: 30
    )
    other_agent_profile = other_tenant.profiles.find_by!(key: "agent")
    other_agent = create(:admin_user, tenant: other_tenant, profile: other_agent_profile, active: true)
    current_lead = create(:lead, tenant: tenant, phone: "5547999990000", admin_user: nil)
    create(:lead, tenant: other_tenant, phone: "5547999990000", admin_user: other_agent, updated_at: 1.day.ago)
    rule = create(:distribution_rule, tenant: tenant)

    result = described_class.corretor_for(current_lead, rule, candidates: [])

    expect(result).to be_nil
  end

  it "reaproveita corretor anterior apenas dentro do mesmo tenant" do
    LeadSetting.instance.update!(
      stickiness_enabled: true,
      stickiness_match: "phone",
      stickiness_owner: "any_assignment",
      stickiness_fallback: "active_any",
      stickiness_window_days: 30
    )
    agent_profile = tenant.profiles.find_by!(key: "agent")
    agent = create(:admin_user, tenant: tenant, profile: agent_profile, active: true)
    current_lead = create(:lead, tenant: tenant, phone: "5547999990000", admin_user: nil)
    create(:lead, tenant: tenant, phone: "5547999990000", admin_user: agent, updated_at: 1.day.ago)
    rule = create(:distribution_rule, tenant: tenant)

    result = described_class.corretor_for(current_lead, rule, candidates: [])

    expect(result).to eq(agent)
  end
end
