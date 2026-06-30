require "rails_helper"

RSpec.describe AttributeOption, type: :model do
  it "isola unicidade por Tenant" do
    tenant = Tenant.create!(name: "Catalog tenant #{SecureRandom.hex(3)}", slug: "catalog-tenant-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Other catalog tenant #{SecureRandom.hex(3)}", slug: "other-catalog-tenant-#{SecureRandom.hex(3)}")

    tenant.attribute_options.create!(context: "lead", category: "source", name: "Instagram")
    other_option = other_tenant.attribute_options.build(context: "lead", category: "source", name: "Instagram")
    duplicate = tenant.attribute_options.build(context: "lead", category: "source", name: "Instagram")

    expect(other_option).to be_valid
    expect(duplicate).not_to be_valid
  end
end
