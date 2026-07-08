require "rails_helper"

RSpec.describe Proprietors::DuplicateMerger do
  let(:tenant) { Tenant.create!(name: "Tenant merge #{SecureRandom.hex(3)}", slug: "tenant-merge-#{SecureRandom.hex(3)}") }

  def create_proprietor(**attrs)
    create(
      :proprietor,
      {
        tenant: tenant,
        phone_primary: nil,
        mobile_phone: nil,
        residential_phone: nil,
        business_phone: nil,
        vista_code: SecureRandom.hex(5)
      }.merge(attrs)
    )
  end

  it "reaponta referências e remove duplicado quando executado" do
    canonical = create_proprietor(name: "Dono Um", email: "dono@example.com", city: nil)
    duplicate = create_proprietor(name: "Dono Um", email: "DONO@example.com", city: "Balneário Camboriú")
    create(:habitation, tenant: tenant, proprietor: canonical, codigo: "95#{SecureRandom.random_number(10**8)}")
    create(:habitation, tenant: tenant, proprietor: canonical, codigo: "94#{SecureRandom.random_number(10**8)}")
    habitation = create(:habitation, tenant: tenant, proprietor: duplicate, codigo: "97#{SecureRandom.random_number(10**8)}")
    candidate = Proprietors::DuplicateAnalyzer.new(tenant_scope: Tenant.where(id: tenant.id)).call.find do |item|
      item.match_type == "email" && item.match_key == "dono@example.com"
    end

    result = described_class.new(candidates: [candidate], risks: ["automatic_candidate"], execute: true).call

    expect(result.deleted).to eq(1)
    expect(result.repointed).to eq(1)
    expect(habitation.reload.proprietor_id).to eq(canonical.id)
    expect(Proprietor.exists?(duplicate.id)).to be(false)
    expect(canonical.reload.city).to eq("Balneário Camboriú")
  end

  it "não altera dados em dry-run" do
    canonical = create_proprietor(name: "Dono Dois", email: "dois@example.com")
    duplicate = create_proprietor(name: "Dono Dois", email: "DOIS@example.com")
    create(:habitation, tenant: tenant, proprietor: canonical, codigo: "93#{SecureRandom.random_number(10**8)}")
    create(:habitation, tenant: tenant, proprietor: canonical, codigo: "92#{SecureRandom.random_number(10**8)}")
    habitation = create(:habitation, tenant: tenant, proprietor: duplicate, codigo: "96#{SecureRandom.random_number(10**8)}")
    candidate = Proprietors::DuplicateAnalyzer.new(tenant_scope: Tenant.where(id: tenant.id)).call.find do |item|
      item.match_type == "email" && item.match_key == "dois@example.com"
    end

    result = described_class.new(candidates: [candidate], risks: ["automatic_candidate"], execute: false).call

    expect(result.deleted).to eq(1)
    expect(result.repointed).to eq(1)
    expect(habitation.reload.proprietor_id).to eq(duplicate.id)
    expect(Proprietor.exists?(duplicate.id)).to be(true)
    expect(Proprietor.exists?(canonical.id)).to be(true)
  end
end
