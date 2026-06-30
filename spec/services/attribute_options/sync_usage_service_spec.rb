require "rails_helper"

RSpec.describe AttributeOptions::SyncUsageService do
  let(:tenant) { Tenant.create!(name: "Tenant catalogo #{SecureRandom.hex(3)}", slug: "tenant-catalogo-#{SecureRandom.hex(3)}") }
  let(:other_tenant) { Tenant.create!(name: "Outro catalogo #{SecureRandom.hex(3)}", slug: "outro-catalogo-#{SecureRandom.hex(3)}") }

  it "renomeia origem de leads apenas no tenant informado" do
    lead = create(:lead, tenant: tenant, origin: "Instagram antigo")
    other_lead = create(:lead, tenant: other_tenant, origin: "Instagram antigo")

    described_class.new(
      tenant: tenant,
      context: "lead",
      category: "source",
      old_name: "Instagram antigo",
      new_name: "Instagram",
      action: :rename
    ).call

    expect(lead.reload.origin).to eq("Instagram")
    expect(other_lead.reload.origin).to eq("Instagram antigo")
  end

  it "remove origem de leads apenas no tenant corrente" do
    lead = create(:lead, tenant: tenant, origin: "Evento")
    other_lead = create(:lead, tenant: other_tenant, origin: "Evento")

    Current.set(tenant: tenant) do
      described_class.new(
        context: "lead",
        category: "source",
        old_name: "Evento",
        action: :delete
      ).call
    end

    expect(lead.reload.origin).to be_nil
    expect(other_lead.reload.origin).to eq("Evento")
  end
end
