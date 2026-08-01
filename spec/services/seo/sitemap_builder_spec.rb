require "rails_helper"

RSpec.describe Seo::SitemapBuilder do
  describe "#to_xml" do
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
