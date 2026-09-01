require "rails_helper"

RSpec.describe DistributionRule, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  def create_tenant_with_agent_profile(slug)
    tenant = Tenant.create!(name: slug.titleize, slug: slug)
    profile = tenant.profiles.find_by!(key: "agent")
    [tenant, profile]
  end

  it "compacta as posicoes depois de rotacionar a fila" do
    tenant, profile = create_tenant_with_agent_profile("tenant-rotacao-fila")
    rule = create(:distribution_rule, tenant: tenant, distribution_mode: :rotary)
    first_user = create(:admin_user, tenant: tenant, profile: profile, email: "primeiro@example.com")
    second_user = create(:admin_user, tenant: tenant, profile: profile, email: "segundo@example.com")
    third_user = create(:admin_user, tenant: tenant, profile: profile, email: "terceiro@example.com")
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: first_user, position: 97)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: second_user, position: 98)
    create(:distribution_rule_agent, distribution_rule: rule, admin_user: third_user, position: 99)

    travel_to Time.zone.local(2026, 9, 1, 10, 0, 0) do
      rule.rotate_queue!(first_user.id)
    end

    expect(rule.distribution_rule_agents.order(:position).pluck(:admin_user_id, :position)).to eq([
      [second_user.id, 1],
      [third_user.id, 2],
      [first_user.id, 3]
    ])
  end
end
