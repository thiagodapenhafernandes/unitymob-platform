require "rails_helper"

RSpec.describe PropertyReviewPolicy::ImpactReport do
  it "conta somente captações em andamento do tenant informado" do
    tenant = Tenant.create!(name: "Política A", slug: "politica-a-#{SecureRandom.hex(3)}", active: true)
    other = Tenant.create!(name: "Política B", slug: "politica-b-#{SecureRandom.hex(3)}", active: true)
    setting = PropertySetting.instance(tenant: tenant)
    owner = create(:admin_user, :admin, tenant: tenant)
    other_owner = create(:admin_user, :admin, tenant: other)
    create(:habitation, :broker_intake, tenant: tenant, admin_user: owner, intake_status: "draft")
    create(:habitation, :broker_intake, tenant: tenant, admin_user: owner, intake_status: "submitted_for_admin_review")
    create(:habitation, :broker_intake, tenant: tenant, admin_user: owner, intake_status: "published")
    create(:habitation, :broker_intake, tenant: other, admin_user: other_owner, intake_status: "submitted_for_admin_review")

    report = described_class.call(tenant: tenant, setting: setting)

    expect(report).to include("in_progress" => 2, "awaiting_review" => 1)
  end
end
