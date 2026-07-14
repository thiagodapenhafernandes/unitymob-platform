require "rails_helper"

RSpec.describe PresentationCard, type: :model do
  describe "#company_display_name" do
    it "usa a identidade visual do tenant do cartão mesmo com outro tenant no contexto" do
      card_tenant = Tenant.create!(name: "Conta do cartão", slug: "conta-cartao-#{SecureRandom.hex(4)}")
      context_tenant = Tenant.create!(name: "Conta do contexto", slug: "conta-contexto-#{SecureRandom.hex(4)}")
      card_user = create(:admin_user, tenant: card_tenant, email: "card-owner-#{SecureRandom.hex(4)}@example.com")
      LayoutSetting.instance(tenant: card_tenant).update!(site_name: "Marca correta")
      LayoutSetting.instance(tenant: context_tenant).update!(site_name: "Marca externa")
      card = described_class.create!(
        tenant: card_tenant,
        admin_user: card_user,
        label: "Apresentação",
        greeting: "Olá, sou {nome} da {empresa}.",
        active: true
      )

      company = Current.set(tenant: context_tenant) { card.company_display_name }

      expect(company).to eq("Marca correta")
      expect(card.greeting_for(card_user)).to include("Marca correta")
      expect(card.greeting_for(card_user)).not_to include("Marca externa")
    end
  end
end
