require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  it "resolves the same title for page metadata and listing schema, preserving manual SEO" do
    assign(:page_title, "Busca regional")
    assign(:page_title_priority, true)
    seo = instance_double(SeoSetting, public_applicable?: true, manual_mode?: false, meta_title: "Título automático")
    expect(helper.public_seo_title(seo)).to eq("Busca regional")
    allow(seo).to receive(:manual_mode?).and_return(true)
    expect(helper.public_seo_title(seo)).to eq("Título automático")
    expect(helper.public_seo_title(seo, property_page: true)).to eq("Busca regional")
  end

  it "publishes the account logo and each branch city" do
    tenant = Tenant.default
    helper.define_singleton_method(:public_tenant) { tenant }
    layout = LayoutSetting.instance(tenant: tenant)
    layout.logo.attach(io: File.open(Rails.root.join("spec/fixtures/files/watermark.png")), filename: "logo.png", content_type: "image/png")
    tenant.stores.create!(name: "Recife", address: "Rua A", city: "Recife", state: "PE")
    tenant.stores.create!(name: "Curitiba", address: "Rua B", city: "Curitiba", state: "PR")
    profile = PublicSiteProfile.current(tenant: tenant)
    profile.creci = "4321-J"
    profile.save
    tenant.tenant_domains.create!(hostname: "conexaobc.com", primary_domain: true)
    schema = helper.real_estate_agent_schema
    expect(schema["identifier"]["value"]).to eq("4321-J")
    expect(schema["url"]).to eq("https://conexaobc.com")
    expect(helper.public_website_schema["publisher"]["@id"]).to eq(schema["@id"])
    expect(schema["logo"]).to be_present
    expect(schema["logo"]).to include("logo.png")
    expect(schema["subOrganization"].map { |branch| branch["@id"] }.uniq.size).to eq(2)
    expect(schema["subOrganization"].map { |branch| branch["@type"] }).to eq(["RealEstateAgent", "RealEstateAgent"])
    expect(schema["location"].map { |l| l["address"]["addressLocality"] }).to eq(["Recife", "Curitiba"])
  end
end
