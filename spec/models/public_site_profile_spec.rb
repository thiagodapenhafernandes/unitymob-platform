require "rails_helper"

RSpec.describe PublicSiteProfile do
  it "lê os dados públicos persistidos no tenant padrão" do
    tenant = Tenant.default
    described_class::FIELDS.each do |field|
      value = {
        primary_city: "Balneário Camboriú",
        legal_name: "Salute Locação de Imóveis Ltda - ME",
        legal_document: "63.057.499/0001-93",
        creci: "6834"
      }[field]
      Setting.set("#{described_class::PREFIX}.#{field}", value, tenant: tenant) if value
    end

    profile = described_class.current(tenant: tenant)

    expect(profile).to have_attributes(
      primary_city: "Balneário Camboriú",
      legal_name: "Salute Locação de Imóveis Ltda - ME",
      legal_document: "63.057.499/0001-93",
      creci: "6834"
    )
  end

  it "não replica os fallbacks da Salute para outros tenants" do
    tenant = Tenant.create!(name: "Imobiliária Nova", slug: "nova-#{SecureRandom.hex(4)}")

    profile = described_class.current(tenant: tenant)

    expect(profile.primary_city).to be_blank
    expect(profile.legal_name).to be_blank
    expect(profile.legal_document).to be_blank
    expect(profile.creci).to be_blank
  end

  it "salva e lê as configurações isoladas por tenant" do
    first = Tenant.create!(name: "Conta Um", slug: "conta-um-#{SecureRandom.hex(4)}")
    second = Tenant.create!(name: "Conta Dois", slug: "conta-dois-#{SecureRandom.hex(4)}")

    described_class.new({ primary_city: "Curitiba", legal_name: "Conta Um Ltda" }, tenant: first).save
    described_class.new({ primary_city: "Recife", legal_name: "Conta Dois Ltda" }, tenant: second).save

    expect(described_class.current(tenant: first)).to have_attributes(primary_city: "Curitiba", legal_name: "Conta Um Ltda")
    expect(described_class.current(tenant: second)).to have_attributes(primary_city: "Recife", legal_name: "Conta Dois Ltda")
  end

  it "rejeita faixas de preço fora do contrato Nome|mínimo|máximo" do
    tenant = Tenant.create!(name: "Conta Faixas", slug: "faixas-#{SecureRandom.hex(4)}")
    profile = described_class.new({ sale_price_ranges: "Até um milhão|valor inválido|1000000" }, tenant: tenant)

    expect(profile).not_to be_valid
    expect(profile.errors[:sale_price_ranges]).to include("linha 1 deve usar Nome|mínimo|máximo")
  end

  it "valida e estrutura links úteis persistidos" do
    tenant = Tenant.create!(name: "Conta Links", slug: "links-#{SecureRandom.hex(4)}")
    profile = described_class.new(
      { useful_links: "Prefeitura|https://cidade.example.gov.br|Portal municipal|building" },
      tenant: tenant
    )

    expect(profile).to be_valid
    expect(profile.useful_link_options).to eq([
      { label: "Prefeitura", url: "https://cidade.example.gov.br", description: "Portal municipal", icon: "building" }
    ])
  end
end
