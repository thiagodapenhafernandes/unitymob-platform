require "rails_helper"

RSpec.describe "Home organization schema", type: :request do
  before { host! "localhost" }

  it "emite RealEstateAgent com os dados do tenant e JSON válido" do
    tenant = Tenant.default
    LayoutSetting.instance(tenant: tenant).update!(site_name: "Schema Imóveis")
    ContactSetting.instance(tenant: tenant).update!(
      phone: "(47) 3311-1067",
      whatsapp_primary: "(47) 98811-3063",
      email_primary: "contato@schemaimoveis.com.br",
      instagram_url: "https://www.instagram.com/schemaimoveis/"
    )
    FooterSetting.instance(tenant: tenant).footer_stores.create!(name: "Matriz", address: "Avenida Atlântica, 3750")
    Setting.set("public_site.profile.primary_city", "Balneário Camboriú", "Perfil público", tenant: tenant)
    tenant.seo_settings.create!(
      page_name: "home", active: true, apply_to_public: true,
      meta_description: "Imobiliária especializada em venda e locação."
    )

    get root_path

    expect(response).to have_http_status(:ok)
    schemas = Nokogiri::HTML(response.body).css('script[type="application/ld+json"]').map { |node| JSON.parse(node.text) }
    agent = schemas.find { |schema| Array(schema["@type"]).include?("RealEstateAgent") }

    expect(agent["@id"]).to eq("http://localhost#organization")
    expect(agent["name"]).to eq("Schema Imóveis")
    expect(agent["address"]).to include("streetAddress" => "Avenida Atlântica, 3750", "addressLocality" => "Balneário Camboriú", "addressCountry" => "BR")
    expect(agent["url"]).to eq("http://localhost")
    expect(agent["description"]).to eq("Imobiliária especializada em venda e locação.")
    expect(agent["telephone"]).to eq("+554733111067")
    expect(agent["email"]).to eq("contato@schemaimoveis.com.br")
    expect(agent["sameAs"]).to include("https://www.instagram.com/schemaimoveis/")
    expect(agent["contactPoint"].map { |point| point["telephone"] }).to eq(["+554733111067", "+5547988113063"])
    expect(agent["areaServed"]).to eq({ "@type" => "City", "name" => "Balneário Camboriú" })
    expect(agent["hasMap"]).to start_with("https://maps.google.com/?q=")
    expect(agent["location"].first.dig("address", "streetAddress")).to eq("Avenida Atlântica, 3750")
  end
end
