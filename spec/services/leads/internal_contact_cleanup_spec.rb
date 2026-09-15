require "rails_helper"

RSpec.describe Leads::InternalContactCleanup do
  it "remove leads com telefone de usuario interno e preserva clientes reais" do
    tenant = Tenant.create!(name: "Tenant limpeza interna #{SecureRandom.hex(3)}", slug: "tenant-limpeza-interna-#{SecureRandom.hex(3)}")
    internal_user = create(:admin_user, tenant: tenant, phone: "(47) 98489-5559")
    internal_lead = create(:lead, tenant: tenant, phone: "5547984895559", name: internal_user.name)
    client_lead = create(:lead, tenant: tenant, phone: "5547999998888", name: "Cliente Real")

    dry_run = described_class.call(tenant: tenant, execute: false)

    expect(dry_run.first.matched_count).to eq(1)
    expect(dry_run.first.removed_count).to eq(0)
    expect(Lead.exists?(internal_lead.id)).to be(true)

    execute = described_class.call(tenant: tenant, execute: true)

    expect(execute.first.matched_count).to eq(1)
    expect(execute.first.removed_count).to eq(1)
    expect(Lead.exists?(internal_lead.id)).to be(false)
    expect(Lead.exists?(client_lead.id)).to be(true)
  end

  it "respeita o tenant ao comparar telefones" do
    tenant = Tenant.create!(name: "Tenant limpeza A #{SecureRandom.hex(3)}", slug: "tenant-limpeza-a-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Tenant limpeza B #{SecureRandom.hex(3)}", slug: "tenant-limpeza-b-#{SecureRandom.hex(3)}")
    create(:admin_user, tenant: tenant, phone: "(47) 98489-5559")
    other_lead = create(:lead, tenant: other_tenant, phone: "5547984895559", name: "Cliente Outro Tenant")

    result = described_class.call(tenant: other_tenant, execute: true)

    expect(result.first.matched_count).to eq(0)
    expect(Lead.exists?(other_lead.id)).to be(true)
  end
end
