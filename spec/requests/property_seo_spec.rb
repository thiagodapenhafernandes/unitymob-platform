require "rails_helper"

RSpec.describe "Property SEO", type: :request do
  before { host! "localhost" }

  it "keeps full titles and consistent descriptions, canonical schema and breadcrumbs" do
    title = "Apartamento com vista para o mar e quatro suítes no Centro de Balneário Camboriú"
    property = create(:habitation, meta_title: title, meta_description: "Descrição manual do imóvel.")
    get habitation_path(property), params: { utm_source: "campaign" }
    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css("title").text).to include(title)
    schemas = page.css('script[type="application/ld+json"]').map { |node| JSON.parse(node.text) }
    listing = schemas.find { |schema| schema["@type"] == "RealEstateListing" }
    canonical = page.at_css('link[rel="canonical"]')["href"]
    expect(listing["url"]).to eq(canonical)
    expect(listing.dig("offers", "url")).to eq(canonical)
    expect(listing["description"]).to eq(page.at_css('meta[name="description"]')["content"])
    expect(schemas.find { |schema| schema["@type"] == "BreadcrumbList" }.fetch("itemListElement").last["item"]).to eq(canonical)
    expect(page.at_css('meta[name="robots"]')["content"]).to include("max-image-preview:large")
  end

  it "keeps page three crawlable with its own canonical" do
    create_list(:habitation, 25)
    get habitations_path, params: { page: 3, utm_source: "campaign" }
    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    expect(page.at_css('meta[name="robots"]')["content"]).not_to include("noindex")
    expect(page.at_css('link[rel="canonical"]')["href"]).to eq("http://localhost/imoveis?page=3")
    get "/robots.txt"
    expect(response.body).not_to include("Disallow: /imoveis?")
  end

  it "uses the property's tenant brand even outside the current tenant" do
    tenant = Tenant.create!(name: "Outra conta", slug: "seo-other")
    LayoutSetting.instance(tenant: tenant).update!(site_name: "Outra marca")
    property = create(:habitation, tenant: tenant)
    expect(Seo::PropertyMetadataBuilder.new(property).attributes[:meta_title]).to end_with(" | Outra marca")
  end
end
