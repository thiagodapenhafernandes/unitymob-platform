require "rails_helper"

RSpec.describe Dwv::ProprietorResolver do
  let(:tenant) { Tenant.create!(name: "Tenant proprietário DWV #{SecureRandom.hex(3)}", slug: "tenant-proprietario-dwv-#{SecureRandom.hex(3)}") }

  it "cria proprietário construtora quando não existe cadastro equivalente" do
    result = described_class.new(
      tenant: tenant,
      name: "Platinum Incorporadora",
      phone_primary: "(47) 99653-7303"
    ).call

    expect(result.action).to eq(:created)
    expect(result.proprietor).to be_persisted
    expect(result.proprietor.name).to eq("Platinum Incorporadora")
    expect(result.proprietor).to be_role_builder
    expect(result.proprietor.phone_primary).to eq("5547996537303")
  end

  it "reaproveita o melhor proprietário quando já existem duplicados com o mesmo nome" do
    weak = create(:proprietor, tenant: tenant, name: "Platinum", vista_code: "37139", phone_primary: nil, email: nil)
    canonical = create(:proprietor, tenant: tenant, name: "Platinum", vista_code: "37140", phone_primary: "(47) 99653-7303")
    create(:habitation, tenant: tenant, proprietor: canonical)

    result = described_class.new(tenant: tenant, name: "Platinum").call

    expect(result.action).to eq(:matched)
    expect(result.matched_by).to eq(:name)
    expect(result.proprietor).to eq(canonical)
    expect(result.proprietor).not_to eq(weak)
  end

  it "não cria proprietário em dry-run" do
    expect do
      result = described_class.new(tenant: tenant, name: "Construtora Nova", persist: false).call
      expect(result.action).to eq(:would_create)
      expect(result.proprietor).to be_nil
    end.not_to change(Proprietor, :count)
  end
end
