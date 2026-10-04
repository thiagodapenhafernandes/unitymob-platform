require "rails_helper"

RSpec.describe Seo::StrategicLanding do
  it "uses the account region in development introductions" do
    tenant = Tenant.create!(name: "Conta Recife", slug: "intro-recife-#{SecureRandom.hex(3)}")
    PublicSiteProfile.new({ primary_city: "Recife" }, tenant: tenant).save
    text = described_class.development_intro({ title: "Novos empreendimentos" }, tenant: tenant)
    expect(text).to include("Recife e região")
    expect(text).not_to include("litoral catarinense", "Salute")
  end

  it "oferece o atalho de bairro para a conta que tem imóvel lá, qualquer que seja o slug" do
    tenant = Tenant.create!(name: "Imobiliária Litoral", slug: "litoral-#{SecureRandom.hex(4)}")
    create(:habitation, tenant:, exibir_no_site_flag: true,
                        address_attributes: { logradouro: "Av. Brasil", numero: "1", bairro: "Centro", cidade: "Balneário Camboriú", uf: "SC" })

    property_slugs = described_class.property_links(tenant: tenant).pluck(:slug)

    expect(property_slugs).to include("centro", "frente-mar")
    expect(property_slugs).not_to include("barra-sul", "praia-brava")
    expect(described_class.property("centro", tenant: tenant)).to be_present
    expect(described_class.property("barra-sul", tenant: tenant)).to be_nil
  end

  it "não oferece bairros onde a conta não tem imóvel" do
    tenant = Tenant.create!(name: "Imobiliária Curitiba", slug: "seo-curitiba-#{SecureRandom.hex(4)}")
    expect(PublicSiteProfile.new({ primary_city: "Curitiba" }, tenant: tenant).save).to be(true)

    property_links = described_class.property_links(tenant: tenant)
    development_links = described_class.development_links(tenant: tenant)

    expect(property_links.pluck(:slug)).to include("frente-mar", "lancamentos")
    expect(property_links.pluck(:slug)).not_to include("centro", "barra-sul", "praia-brava")
    expect(development_links.pluck(:slug)).not_to include("balneario-camboriu", "centro", "barra-sul", "praia-brava")
    expect(described_class.property("frente-mar", tenant: tenant)[:description]).to include("Curitiba")
  end
end
