require "rails_helper"

RSpec.describe PropertyReviewPolicyAuditLog, type: :model do
  it "rejeita associações pertencentes a outro tenant" do
    tenant = Tenant.create!(name: "Auditoria A", slug: "auditoria-a-#{SecureRandom.hex(3)}", active: true)
    other = Tenant.create!(name: "Auditoria B", slug: "auditoria-b-#{SecureRandom.hex(3)}", active: true)
    setting = PropertySetting.instance(tenant: tenant)
    other_admin = create(:admin_user, :admin, tenant: other)

    audit = described_class.new(tenant: tenant, property_setting: setting, admin_user: other_admin, version: 2, changeset: { "field" => { "before" => true, "after" => false } }, impact_snapshot: { "in_progress" => 0 })

    expect(audit).not_to be_valid
    expect(audit.errors[:admin_user]).to include("deve pertencer à mesma conta")
  end
end
