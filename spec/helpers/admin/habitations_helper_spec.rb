require "rails_helper"

RSpec.describe Admin::HabitationsHelper, type: :helper do
  before do
    helper.remove_instance_variable(:@publication_channel_columns) if helper.instance_variable_defined?(:@publication_channel_columns)
  end

  def create_helper_habitation(**attrs)
    create(
      :habitation,
      {
        codigo: "98#{SecureRandom.random_number(10**8).to_s.rjust(8, '0')}",
        endereco: "Rua Helper #{SecureRandom.hex(4)}"
      }.merge(attrs)
    )
  end

  describe "#admin_habitation_publication_channels" do
    it "returns the site and active portal labels" do
      habitation = Habitation.new(
        exibir_no_site_flag: true,
        publicar_imovelweb: true,
        publicar_viva_real_vrsync: false,
        publicar_loft: true
      )

      expect(helper.admin_habitation_publication_channels(habitation)).to include("Site", "Imovelweb", "Loft")
      expect(helper.admin_habitation_publication_channels(habitation)).not_to include("Viva Real")
    end

    it "humanizes future publication flags without hardcoding the label" do
      allow(Habitation).to receive(:column_names).and_return(Habitation.column_names + ["publicar_portal_novo"])
      habitation = double("Habitation", publicar_portal_novo: true)
      allow(habitation).to receive(:respond_to?) { |method_name| method_name == :publicar_portal_novo }

      expect(helper.admin_habitation_publication_channels(habitation)).to include("Portal novo")
    end

    it "returns no channels when no publication flag is active" do
      habitation = Habitation.new(exibir_no_site_flag: false)

      expect(helper.admin_habitation_publication_channels(habitation)).to be_empty
    end
  end

  describe "#admin_habitation_internal_path" do
    it "returns the edit path when the current user can edit the property" do
      admin = create(:admin_user, :admin)
      habitation = create_helper_habitation(admin_user: admin)

      allow(helper).to receive(:current_admin_user).and_return(admin)

      expect(helper.admin_habitation_internal_path(habitation)).to eq(edit_admin_habitation_path(habitation.id))
    end

    it "returns the internal show path when the current user can only view the property" do
      broker_profile = Profile.create!(
        tenant: Tenant.default,
        name: "Corretor helper #{SecureRandom.hex(6)}",
        permissions: Profile.default_permissions_for("Corretor")
      )
      current_broker = create(:admin_user, profile: broker_profile, name: "Vera Corretora")
      other_broker = create(:admin_user, profile: broker_profile, name: "Outro Corretor")
      habitation = create_helper_habitation(admin_user: other_broker, corretor_nome: "Outro Corretor")

      allow(helper).to receive(:current_admin_user).and_return(current_broker)

      expect(helper.admin_habitation_internal_path(habitation)).to eq(admin_habitation_path(habitation.id))
    end

    it "preserves the return path on internal navigation" do
      admin = create(:admin_user, :admin)
      habitation = create_helper_habitation(admin_user: admin)

      allow(helper).to receive(:current_admin_user).and_return(admin)

      expect(helper.admin_habitation_internal_path(habitation, return_to: "/admin/habitations?ownership=all"))
        .to eq(edit_admin_habitation_path(habitation.id) + "?return_to=/admin/habitations&ownership=all")
    end

    it "flattens return query and back anchor on internal navigation" do
      admin = create(:admin_user, :admin)
      habitation = create_helper_habitation(admin_user: admin)

      allow(helper).to receive(:current_admin_user).and_return(admin)

      path = helper.admin_habitation_path_with_query(
        edit_admin_habitation_path(habitation.id, anchor: "features"),
        helper.admin_habitation_flat_return_params("/admin/habitations?ownership=all&page=3#habitation_#{habitation.id}")
      )

      expect(path)
        .to eq("#{edit_admin_habitation_path(habitation.id)}?return_to=/admin/habitations&ownership=all&page=3&back_anchor=habitation_#{habitation.id}#features")
    end
  end

  describe "#admin_habitation_catalog_card_path" do
    it "returns the edit path on the all tab when the user can edit" do
      broker = create(:admin_user, name: "Vera Corretora")
      habitation = create_helper_habitation(admin_user: broker)

      allow(helper).to receive(:current_admin_user).and_return(broker)

      expect(
        helper.admin_habitation_catalog_card_path(
          habitation,
          ownership_scope: "all",
          intake_review: nil,
          return_to: "/admin/habitations?ownership=all"
        )
      ).to eq(edit_admin_habitation_path(habitation.id) + "?return_to=/admin/habitations&ownership=all")
    end

    it "returns the edit path on the mine tab when the user can edit" do
      broker = create(:admin_user, name: "Vera Corretora")
      habitation = create_helper_habitation(admin_user: broker)

      allow(helper).to receive(:current_admin_user).and_return(broker)

      expect(
        helper.admin_habitation_catalog_card_path(
          habitation,
          ownership_scope: "mine",
          intake_review: nil,
          return_to: "/admin/habitations?ownership=mine"
        )
      ).to eq(edit_admin_habitation_path(habitation.id) + "?return_to=/admin/habitations&ownership=mine")
    end
  end
end
