require 'rails_helper'

RSpec.describe ManualCheckinRequest, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:justification) }

    it "rejeita loja de outra conta (mesmo tenant obrigatório)" do
      tenant = Tenant.create!(name: "Tenant manual #{SecureRandom.hex(3)}", slug: "tenant-manual-#{SecureRandom.hex(3)}")
      other_tenant = Tenant.create!(name: "Outro manual #{SecureRandom.hex(3)}", slug: "outro-manual-#{SecureRandom.hex(3)}")
      user = create(:admin_user, :field_agent, tenant: tenant)
      foreign_store = create(:store, tenant: other_tenant)

      request = build(:manual_checkin_request, tenant: tenant, admin_user: user, store: foreign_store)

      expect(request).not_to be_valid
      expect(request.errors[:store]).to include("deve pertencer à mesma conta")
    end

    it "aceita loja da mesma conta" do
      tenant = Tenant.create!(name: "Tenant manual ok #{SecureRandom.hex(3)}", slug: "tenant-manual-ok-#{SecureRandom.hex(3)}")
      user = create(:admin_user, :field_agent, tenant: tenant)
      store = create(:store, tenant: tenant)

      request = build(:manual_checkin_request, tenant: tenant, admin_user: user, store: store)

      expect(request).to be_valid
    end
  end
end
