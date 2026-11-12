require "rails_helper"
require_relative "../support/sitemap_snapshots"

RSpec.describe "Sitemaps", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include_context "isolated sitemap snapshots"

  it "reuses the sitemap across requests at different times" do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    Seo::SitemapCache.refresh!(tenant: Tenant.default, base_url: "http://localhost")
    expect(Seo::SitemapBuilder).not_to receive(:new)
    host! "localhost"
    get "/sitemap.xml"
    travel 2.seconds do
      get "/sitemap.xml"
    end
    expect(response).to have_http_status(:ok)
  end

  it "asks the crawler to retry without blocking when no snapshot exists yet" do
    host! "localhost"
    expect(Seo::SitemapBuilder).not_to receive(:new)
    expect(Seo::SitemapRefreshJob).to receive(:perform_later).with(Tenant.default.id, "http://localhost")
    get "/sitemap.xml"
    expect(response).to have_http_status(:service_unavailable)
    expect(response.headers["Retry-After"]).to eq("30")
    expect(response.headers["Cache-Control"]).to include("no-store")
  end

  it "returns 304 when the sitemap has not changed" do
    host! "localhost"
    Seo::SitemapCache.refresh!(tenant: Tenant.default, base_url: "http://localhost")
    get "/sitemap.xml"
    get "/sitemap.xml", headers: { "If-None-Match" => response.headers.fetch("ETag") }
    expect(response).to have_http_status(:not_modified)
  end

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
    Seo::SitemapCache.refresh!(tenant: tenant, base_url: "https://conexaobc.com")

    get "/sitemap.xml"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/xml")
    expect(response.body).to include("https://conexaobc.com/imoveis")
    expect(response.body).to include("https://conexaobc.com/imoveis/#{habitation.slug}")
    expect(response.body).not_to include("http://localhost")
    expect(response.body).not_to include("/selecoes/token-sitemap-hidden")
  end
end
