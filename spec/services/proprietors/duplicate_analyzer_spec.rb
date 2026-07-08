require "rails_helper"

RSpec.describe Proprietors::DuplicateAnalyzer do
  let(:tenant) { Tenant.create!(name: "Tenant dedupe #{SecureRandom.hex(3)}", slug: "tenant-dedupe-#{SecureRandom.hex(3)}") }

  def create_proprietor(**attrs)
    create(
      :proprietor,
      {
        tenant: tenant,
        phone_primary: nil,
        mobile_phone: nil,
        residential_phone: nil,
        business_phone: nil,
        email: nil,
        vista_code: SecureRandom.hex(5)
      }.merge(attrs)
    )
  end

  it "classifica CPF ou email repetido como candidato automatico" do
    first = create_proprietor(name: "Pessoa Um", email: "dono@example.com")
    second = create_proprietor(name: "Pessoa Dois", email: "DONO@example.com")

    candidates = described_class.new(tenant_scope: Tenant.where(id: tenant.id)).call
    email_candidate = candidates.find { |candidate| candidate.match_type == "email" && candidate.match_key == "dono@example.com" }

    expect(email_candidate).to be_present
    expect(email_candidate.risk).to eq("automatic_candidate")
    expect([email_candidate.canonical_id] + email_candidate.duplicate_ids).to contain_exactly(first.id, second.id)
  end

  it "classifica telefone repetido como revisão, não automático" do
    create_proprietor(name: "Telefone Um", phone_primary: "(47) 99999-0000")
    create_proprietor(name: "Telefone Dois", mobile_phone: "47 99999-0000")

    candidates = described_class.new(tenant_scope: Tenant.where(id: tenant.id)).call
    phone_candidate = candidates.find { |candidate| candidate.match_type == "phone" && candidate.match_key == "47999990000" }

    expect(phone_candidate).to be_present
    expect(phone_candidate.risk).to eq("review_required")
  end

  it "agrupa família de nome para casos como A10 e A10 Empreendimentos" do
    plain = create_proprietor(name: "A10")
    company = create_proprietor(name: "A10 Empreendimentos")
    real_estate = create_proprietor(name: "A10 Negócios Imobiliários")

    candidates = described_class.new(tenant_scope: Tenant.where(id: tenant.id)).call
    family_candidate = candidates.find { |candidate| candidate.match_type == "name_family" && candidate.match_key == "a10" }

    expect(family_candidate).to be_present
    expect(family_candidate.risk).to eq("review_required")
    expect([family_candidate.canonical_id] + family_candidate.duplicate_ids).to contain_exactly(plain.id, company.id, real_estate.id)
  end
end
