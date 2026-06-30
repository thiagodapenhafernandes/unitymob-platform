require "rails_helper"

RSpec.describe Admin::HabitationsHelper, type: :helper do
  describe "#admin_habitation_internal_path" do
    it "returns the edit path when the current user can edit the property" do
      admin = create(:admin_user, :admin)
      habitation = create(:habitation, admin_user: admin)

      allow(helper).to receive(:current_admin_user).and_return(admin)

      expect(helper.admin_habitation_internal_path(habitation)).to eq(edit_admin_habitation_path(habitation))
    end

    it "returns the internal show path when the current user can only view the property" do
      broker_profile = Profile.create!(
        tenant: Tenant.default,
        name: "Corretor helper #{SecureRandom.hex(6)}",
        permissions: Profile.default_permissions_for("Corretor")
      )
      current_broker = create(:admin_user, profile: broker_profile, name: "Vera Corretora")
      other_broker = create(:admin_user, profile: broker_profile, name: "Outro Corretor")
      habitation = create(:habitation, admin_user: other_broker, corretor_nome: "Outro Corretor")

      allow(helper).to receive(:current_admin_user).and_return(current_broker)

      expect(helper.admin_habitation_internal_path(habitation)).to eq(admin_habitation_path(habitation))
    end

    it "preserves the return path on internal navigation" do
      admin = create(:admin_user, :admin)
      habitation = create(:habitation, admin_user: admin)

      allow(helper).to receive(:current_admin_user).and_return(admin)

      expect(helper.admin_habitation_internal_path(habitation, return_to: "/admin/habitations?ownership=all"))
        .to eq(edit_admin_habitation_path(habitation, return_to: "/admin/habitations?ownership=all"))
    end
  end

  describe "#admin_habitation_catalog_card_path" do
    it "returns the internal show path on the all tab even when the user can edit" do
      broker = create(:admin_user, name: "Vera Corretora")
      habitation = create(:habitation, admin_user: broker)

      allow(helper).to receive(:current_admin_user).and_return(broker)

      expect(
        helper.admin_habitation_catalog_card_path(
          habitation,
          ownership_scope: "all",
          intake_review: nil,
          return_to: "/admin/habitations?ownership=all"
        )
      ).to eq(admin_habitation_path(habitation, return_to: "/admin/habitations?ownership=all"))
    end

    it "returns the edit path on the mine tab when the user can edit" do
      broker = create(:admin_user, name: "Vera Corretora")
      habitation = create(:habitation, admin_user: broker)

      allow(helper).to receive(:current_admin_user).and_return(broker)

      expect(
        helper.admin_habitation_catalog_card_path(
          habitation,
          ownership_scope: "mine",
          intake_review: nil,
          return_to: "/admin/habitations?ownership=mine"
        )
      ).to eq(edit_admin_habitation_path(habitation, return_to: "/admin/habitations?ownership=mine"))
    end
  end
end
