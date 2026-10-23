require "rails_helper"

RSpec.describe DistributionRuleAgent, type: :model do
  def create_tenant_with_agent_profile(slug)
    tenant = Tenant.create!(name: slug.titleize, slug: slug)
    profile = tenant.profiles.find_by!(key: "agent")
    [ tenant, profile ]
  end

  it "bloqueia usuário de outro Tenant na fila de distribuição" do
    tenant, profile = create_tenant_with_agent_profile("tenant-fila-a")
    other_tenant, other_profile = create_tenant_with_agent_profile("tenant-fila-b")
    rule = create(:distribution_rule, tenant: tenant)
    other_user = create(:admin_user, tenant: other_tenant, profile: other_profile)

    agent = described_class.new(distribution_rule: rule, admin_user: other_user, weight: 1)

    expect(agent).not_to be_valid
    expect(agent.errors[:admin_user]).to be_present
  end

  it "bloqueia usuário inativo na fila de distribuição" do
    tenant, profile = create_tenant_with_agent_profile("tenant-fila-inativo")
    rule = create(:distribution_rule, tenant: tenant)
    inactive_user = create(:admin_user, tenant: tenant, profile: profile, active: false)

    agent = described_class.new(distribution_rule: rule, admin_user: inactive_user, weight: 1)

    expect(agent).not_to be_valid
    expect(agent.errors[:admin_user]).to be_present
  end

  it "não permite persistir usuário de conta sem perfil vertical para entrar na fila" do
    tenant, profile = create_tenant_with_agent_profile("tenant-fila-horizontal")
    horizontal = Profile.create!(
      tenant: tenant,
      name: "Atendimento",
      axis: "horizontal",
      vertical_profile: profile,
      permissions: {}
    )
    user = build(:admin_user, tenant: tenant, horizontal_profile: horizontal)
    user.profile = nil

    expect {
      user.save!(validate: false)
    }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "exclui função administrativa horizontal mesmo quando ela tem uma âncora vertical" do
    tenant, profile = create_tenant_with_agent_profile("tenant-fila-administrativo")
    horizontal = Profile.create!(tenant: tenant, name: "Financeiro", axis: "horizontal", vertical_profile: profile)
    user = create(:admin_user, tenant: tenant, horizontal_profile: horizontal)
    rule = create(:distribution_rule, tenant: tenant)
    expect(rule.eligible_distribution_agent?(user)).to be(false)
    expect(rule.eligible_admin_users_scope).not_to include(user)
    expect(described_class.new(distribution_rule: rule, admin_user: user, weight: 1)).not_to be_valid
  end
end
