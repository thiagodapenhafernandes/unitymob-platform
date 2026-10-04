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

    it "keeps the latest property change when SEO already lists its URL" do
      tenant = Tenant.default
      property = create(:habitation, tenant: tenant)
      tenant.seo_settings.create!(page_name: "property-date", canonical_key: "property:#{property.codigo}", page_type: "property_show", canonical_path: "/imoveis/#{property.slug}", canonical_url: "https://example.test/imoveis/#{property.slug}", active: true, apply_to_public: true, robots_index: true, updated_at: 2.days.ago)
      property.update_columns(updated_at: 1.hour.ago)
      xml = described_class.new(base_url: "https://example.test", url_helpers: Rails.application.routes.url_helpers, tenant: tenant).to_xml
      entry = Nokogiri::XML(xml).remove_namespaces!.xpath("//url").find { |node| node.at_xpath("loc").text.end_with?(property.slug) }
      expect(entry.at_xpath("lastmod").text).to eq(property.reload.updated_at.iso8601)
    end

    it "excludes unpublished pages left in the SEO inventory" do
      tenant = Tenant.default
      tenant.seo_settings.create!(page_name: "deleted-page", canonical_key: "landing_pages_show:deleted", page_type: "landing_pages_show", canonical_path: "/deleted-page", canonical_url: "https://example.test/deleted-page?slug=deleted-page", active: true, apply_to_public: true, robots_index: true)
      xml = described_class.new(base_url: "https://example.test", url_helpers: Rails.application.routes.url_helpers, tenant: tenant).to_xml
      expect(xml).not_to include("deleted-page")
    end

    it "excludes obsolete detail aliases even when their SEO page type is wrong" do
      tenant = Tenant.default
      property = create(:habitation, tenant: tenant, codigo: "123456789")
      tenant.seo_settings.create!(page_name: "obsolete-alias", canonical_key: "obsolete-alias", page_type: "property_listing", canonical_path: "/imoveis/#{property.codigo}", canonical_url: "https://example.test/imoveis/#{property.codigo}", active: true, apply_to_public: true, robots_index: true)
      xml = described_class.new(base_url: "https://example.test", url_helpers: Rails.application.routes.url_helpers, tenant: tenant).to_xml
      expect(xml).not_to include("<loc>https://example.test/imoveis/#{property.codigo}</loc>")
      expect(xml).to include("<loc>https://example.test/imoveis/#{property.slug}</loc>")
    end

    it "excludes the financing simulator when disabled for the tenant" do
      tenant = Tenant.default
      allow(PublicSiteProfile).to receive(:current).with(tenant: tenant).and_return(double(financing_simulator_enabled?: false))
      tenant.seo_settings.create!(page_name: "simulator", canonical_key: "simulator", page_type: "pages_simulador", canonical_path: "/simulador-financiamento", canonical_url: "https://example.test/simulador-financiamento", active: true, apply_to_public: true, robots_index: true)
      xml = described_class.new(base_url: "https://example.test", url_helpers: Rails.application.routes.url_helpers, tenant: tenant).to_xml
      expect(xml).not_to include("simulador-financiamento")
    end

    it "does not publish internal IDs for properties without a public slug" do
      tenant = Tenant.default
      property = create(:habitation, tenant: tenant)
      property.update_columns(slug: nil)
      xml = described_class.new(base_url: "https://example.test", url_helpers: Rails.application.routes.url_helpers, tenant: tenant).to_xml
      expect(xml).not_to include("<loc>https://example.test/imoveis/#{property.id}</loc>")
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
