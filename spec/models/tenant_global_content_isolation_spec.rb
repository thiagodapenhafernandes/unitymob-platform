require "rails_helper"

RSpec.describe "Tenant isolation for public content" do
  let!(:tenant_a) { Tenant.create!(name: "Tenant A", slug: "tenant-a-#{SecureRandom.hex(3)}", active: true) }
  let!(:tenant_b) { Tenant.create!(name: "Tenant B", slug: "tenant-b-#{SecureRandom.hex(3)}", active: true) }

  it "isolates landing pages even when tenants use the same slug" do
    page_a = tenant_a.landing_pages.create!(title: "Campanha", slug: "campanha", active: true)
    page_b = tenant_b.landing_pages.create!(title: "Campanha", slug: "campanha", active: true)

    expect(tenant_a.landing_pages.find_by(slug: "campanha")).to eq(page_a)
    expect(tenant_b.landing_pages.find_by(slug: "campanha")).to eq(page_b)
    expect(tenant_a.landing_pages).not_to include(page_b)
  end

  it "isolates webhook destinations and public lead capture flags" do
    tenant_a.webhook_settings.create!(webhook_url: "https://a.example/webhook", enabled: true, lead_capture_enabled: true)
    tenant_b.webhook_settings.create!(webhook_url: "https://b.example/webhook", enabled: true, lead_capture_enabled: false)

    expect(tenant_a.webhook_settings.pluck(:webhook_url)).to contain_exactly("https://a.example/webhook")
    expect(tenant_b.webhook_settings.pluck(:webhook_url)).to contain_exactly("https://b.example/webhook")
    expect(WebhookSetting.lead_capture_enabled?(tenant: tenant_a)).to be(true)
    expect(WebhookSetting.lead_capture_enabled?(tenant: tenant_b)).to be(false)
  end

  it "does not mix SEO records with identical canonical keys" do
    seo_a = tenant_a.seo_settings.create!(page_name: "home", canonical_key: "home")
    seo_b = tenant_b.seo_settings.create!(page_name: "home", canonical_key: "home")

    expect(SeoSetting.for_canonical_key("home", tenant: tenant_a)).to eq(seo_a)
    expect(SeoSetting.for_canonical_key("home", tenant: tenant_b)).to eq(seo_b)
  end

  it "keeps site and lead singleton settings isolated per tenant" do
    layout_a = LayoutSetting.instance(tenant: tenant_a)
    layout_b = LayoutSetting.instance(tenant: tenant_b)
    layout_a.update!(site_name: "Site A")
    layout_b.update!(site_name: "Site B")

    lead_a = LeadSetting.instance(tenant: tenant_a)
    lead_b = LeadSetting.instance(tenant: tenant_b)
    lead_a.update!(stickiness_enabled: true)
    lead_b.update!(stickiness_enabled: false)

    expect(LayoutSetting.instance(tenant: tenant_a).site_name).to eq("Site A")
    expect(LayoutSetting.instance(tenant: tenant_b).site_name).to eq("Site B")
    expect(LeadSetting.instance(tenant: tenant_a).stickiness_enabled?).to be(true)
    expect(LeadSetting.instance(tenant: tenant_b).stickiness_enabled?).to be(false)
  end

  it "does not expose another tenant's content through sitemap services" do
    tenant_a.landing_pages.create!(title: "Página A", slug: "pagina-a", active: true)
    tenant_b.landing_pages.create!(title: "Página B", slug: "pagina-b", active: true)

    xml = Seo::SitemapBuilder.new(
      base_url: "https://tenant-a.example",
      url_helpers: Rails.application.routes.url_helpers,
      tenant: tenant_a
    ).to_xml

    expect(xml).to include("pagina-a")
    expect(xml).not_to include("pagina-b")
  end
end
