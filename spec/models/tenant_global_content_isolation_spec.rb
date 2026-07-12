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
end
