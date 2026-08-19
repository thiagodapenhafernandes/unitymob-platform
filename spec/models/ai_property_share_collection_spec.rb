require "rails_helper"

RSpec.describe AiPropertyShareCollection, type: :model do
  describe ".preview_for_message_body" do
    it "encontra a selecao pelo link publico mantendo escopo do tenant" do
      tenant = Tenant.default
      other_tenant = Tenant.create!(name: "Outro tenant", slug: "outro-tenant")
      admin = create(:admin_user, tenant: tenant)
      other_admin = create(:admin_user, tenant: other_tenant)
      property = create(:habitation, tenant: tenant)
      other_property = create(:habitation, tenant: other_tenant)
      collection = tenant.ai_property_share_collections.create!(admin_user: admin).tap do |share|
        share.habitations << property
      end
      other_collection = other_tenant.ai_property_share_collections.create!(admin_user: other_admin).tap do |share|
        share.habitations << other_property
      end
      body = "Veja esta selecao: https://conexaobc.com/selecoes/#{collection.token}"

      expect(described_class.preview_for_message_body(body, tenant: tenant)).to eq(collection)
      expect(described_class.preview_for_message_body(body, tenant: other_tenant)).to be_nil
      expect(described_class.preview_for_message_body("https://conexaobc.com/selecoes/#{other_collection.token}", tenant: tenant)).to be_nil
    end
  end
end
