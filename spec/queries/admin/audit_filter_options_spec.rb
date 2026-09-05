require "rails_helper"

RSpec.describe Admin::AuditFilterOptions do
  it "respeita IDs autorizados e prioriza o perfil horizontal sem incluir outro tenant" do
    tenant = Tenant.create!(name: "Audit options", slug: "audit-options-#{SecureRandom.hex(4)}")
    other = Tenant.create!(name: "Other audit", slug: "other-audit-#{SecureRandom.hex(4)}")
    vertical = tenant.profiles.find_by!(key: "agent")
    horizontal = Profile.create!(tenant: tenant, name: "Auditor horizontal", axis: "horizontal", vertical_profile: vertical, permissions: {})
    user = create(:admin_user, tenant: tenant, profile: vertical, horizontal_profile: horizontal)
    excluded = create(:admin_user, tenant: tenant, profile: vertical)
    outsider = create(:admin_user, tenant: other)
    query = described_class.new(tenant: tenant, admin_user_ids: [user.id, outsider.id])
    expect(query.users.pluck(:id)).to eq([user.id])
    expect(query.profiles.pluck(:id)).to eq([horizontal.id])
    empty = described_class.new(tenant: tenant, admin_user_ids: [])
    expect(empty.users).to be_empty
    expect(empty.profiles).to be_empty
    unrestricted = described_class.new(tenant: tenant, admin_user_ids: nil)
    expect(unrestricted.users.pluck(:id)).to include(user.id, excluded.id)
    expect(unrestricted.users.pluck(:id)).not_to include(outsider.id)
    expect(unrestricted.profiles.pluck(:id)).to contain_exactly(horizontal.id, vertical.id)
  end
end
