require "rails_helper"

RSpec.describe "Sitemaps", type: :request do
  it "publica URLs no domínio público do tenant" do
    tenant = Tenant.default
    tenant.tenant_domains.create!(hostname: "conexaobc.com", primary_domain: true)
    habitation = create(:habitation, tenant: tenant, codigo: "SITEMAP-PUBLIC", slug: "sitemap-public")
    tenant.seo_settings.create!(
      page_name: "imoveis:sitemap-public",
      canonical_key: "imoveis:sitemap-public",
      page_type: "property_listing",
      canonical_path: "/imoveis",
      canonical_url: "https://conexaobc.com/imoveis",
      active: true,
      apply_to_public: true,
      robots_index: true
    )
    tenant.seo_settings.create!(
      page_name: "ai_property_share_collections_show:sitemap-hidden",
      canonical_key: "ai_property_share_collections_show:sitemap-hidden",
      page_type: "ai_property_share_collections_show",
      canonical_path: "/selecoes/token-sitemap-hidden",
      canonical_url: "https://conexaobc.com/selecoes/token-sitemap-hidden",
      active: true,
      apply_to_public: true,
      robots_index: true
    )
    host! "localhost"

    get "/sitemap.xml"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/xml")
    expect(response.body).to include("https://conexaobc.com/imoveis")
    expect(response.body).to include("https://conexaobc.com/imoveis/#{habitation.slug}")
    expect(response.body).not_to include("http://localhost")
    expect(response.body).not_to include("/selecoes/token-sitemap-hidden")
  end
end
