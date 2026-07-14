require "rails_helper"

RSpec.describe Seo::StrategicLanding do
  it "preserva os atalhos regionais da conta padrão" do
    slugs = described_class.property_links(tenant: Tenant.default).pluck(:slug)

    expect(slugs).to include("centro", "barra-sul", "praia-brava", "frente-mar")
  end

  it "não oferece regiões da Salute para outro tenant" do
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
