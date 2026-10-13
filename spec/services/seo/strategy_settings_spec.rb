require "rails_helper"

RSpec.describe Seo::StrategySettings do
  let(:tenant) { create(:admin_user, :admin).tenant }

  describe ".save!" do
    it "grava flags e prompt da estratégia com as mesmas chaves do inventário" do
      described_class.save!(
        auto_inventory: true,
        auto_apply: false,
        auto_ai: true,
        discovery: false,
        prompt: "Estratégia da conta",
        tenant: tenant
      )

      expect(Seo::PageTracker.enabled?(tenant: tenant)).to be(true)
      expect(Seo::PageTracker.auto_apply?(tenant: tenant)).to be(false)
      expect(Seo::PageTracker.auto_ai?(tenant: tenant)).to be(true)
      expect(Seo::DiscoveryService.enabled?(tenant: tenant)).to be(false)
      expect(Ai::SeoContentService.instructions(tenant: tenant)).to eq("Estratégia da conta")
    end
  end
end
