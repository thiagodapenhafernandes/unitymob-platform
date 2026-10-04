require "rails_helper"

RSpec.describe "Public SEO rendering", type: :request do
  it "renders active account SEO and Open Graph metadata on home and listing" do
    tenant = Tenant.default
    %w[home imoveis].each do |page|
      tenant.seo_settings.create!(
        page_name: page, canonical_key: page, page_type: page == "home" ? "home_index" : "property_listing",
        canonical_path: page == "home" ? "/" : "/imoveis", canonical_url: "http://localhost/#{page == 'home' ? '' : page}",
        meta_title: "#{page} da conta", og_title: "#{page} compartilhado",
        active: true, apply_to_public: true, robots_index: true
      )
    end
    host! "localhost"
    get "/"
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css('link[rel="describedby"]')["href"]).to eq("/llms.txt")
    expect(response.body).to include("<title>home da conta</title>", 'content="home compartilhado"')
    create(:habitation, tenant: tenant)
    get "/imoveis"
    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    schema = html.css('script[type="application/ld+json"]').map { |node| JSON.parse(node.text) }.find { |data| data["@type"] == "ItemList" }
    expect(schema.fetch("name")).to eq(html.at_css("title").text)
  end
end
