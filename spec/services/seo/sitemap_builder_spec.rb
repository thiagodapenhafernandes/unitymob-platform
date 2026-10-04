require "rails_helper"

RSpec.describe Seo::SitemapBuilder do
  describe "#to_xml" do
    it "excludes stale and foreign property SEO entries but preserves available properties" do
      tenant = Tenant.default
      other = Tenant.create!(name: "Other sitemap", slug: "foreign-sitemap-#{SecureRandom.hex(3)}")
      available = create(:habitation, tenant: tenant)
      hidden = create(:habitation, tenant: tenant, exibir_no_site_flag: false)
      foreign = create(:habitation, tenant: other)
      [available, hidden, foreign].each do |property|
        tenant.seo_settings.create!(
          page_name: "imovel:#{property.codigo}", canonical_key: "property:#{property.codigo}",
          page_type: "property_show", canonical_path: "/imoveis/#{property.slug}",
          canonical_url: "https://example.test/imoveis/#{property.slug}",
          active: true, apply_to_public: true, robots_index: true
        )
      end
      xml = described_class.new(base_url: "https://example.test", url_helpers: Rails.application.routes.url_helpers, tenant: tenant).to_xml
      expect(xml.scan("<loc>https://example.test/imoveis/#{available.slug}</loc>").size).to eq(1)
      expect(xml).not_to include("/imoveis/#{hidden.slug}", "/imoveis/#{foreign.slug}")
    end

    it "limits property entries to the provided habitation scope" do
      public_tenant = Tenant.default
      other_tenant = Tenant.create!(
        name: "Outro tenant sitemap #{SecureRandom.hex(3)}",
        slug: "outro-sitemap-#{SecureRandom.hex(3)}"
      )
      scoped_habitation = create(:habitation, tenant: public_tenant, slug: "sitemap-scoped-property")
      other_habitation = create(:habitation, tenant: other_tenant, slug: "sitemap-other-property")

      xml = described_class.new(
        base_url: "https://saluteimoveis.com.br",
        url_helpers: Rails.application.routes.url_helpers,
        tenant: public_tenant,
        habitation_scope: public_tenant.habitations
      ).to_xml

      expect(xml).to include("/imoveis/#{scoped_habitation.slug}")
      expect(xml).not_to include("/imoveis/#{other_habitation.slug}")
    end

    it "uses development detail URLs for public developments" do
      public_tenant = Tenant.default
      development = create(
        :habitation,
        tenant: public_tenant,
        tipo: "Empreendimento",
        nome_empreendimento: "Epic Tower",
        slug: "epic-tower"
      )
      create(
        :habitation,
        tenant: public_tenant,
        codigo_empreendimento: development.codigo,
        status: "Venda",
        exibir_no_site_flag: true,
        valor_venda_cents: 900_000_00,
        pictures: [{ "url" => "https://cdn.example.com/epic.jpg" }]
      )

      xml = described_class.new(
        base_url: "https://saluteimoveis.com.br",
        url_helpers: Rails.application.routes.url_helpers,
        tenant: public_tenant,
        habitation_scope: public_tenant.habitations.where(id: development.id)
      ).to_xml

      expect(xml).to include("https://saluteimoveis.com.br/empreendimento/epic-tower")
      expect(xml).not_to include("https://saluteimoveis.com.br/imoveis/epic-tower")
    end
  end
end
