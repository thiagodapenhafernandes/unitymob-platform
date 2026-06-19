require "rails_helper"

RSpec.describe AdminUser, "governança de dados por equipe", type: :model do
  def profile_with(scope)
    Profile.create!(name: "Perfil #{scope} #{SecureRandom.hex(3)}",
                    permissions: { "leads" => { "view" => true, "scope" => scope } })
  end

  describe "#scope_for / #can_view_team? / #owns_all?" do
    it "reflete o scope configurado no perfil" do
      own  = build(:admin_user, profile: profile_with("own"))
      team = build(:admin_user, profile: profile_with("team"))
      all  = build(:admin_user, profile: profile_with("all"))

      expect(own.scope_for(:leads)).to eq("own")
      expect(team.scope_for(:leads)).to eq("team")
      expect(all.scope_for(:leads)).to eq("all")

      expect(team.can_view_team?(:leads)).to be(true)
      expect(own.can_view_team?(:leads)).to be(false)
      expect(all.owns_all?(:leads)).to be(true)
    end

    it "admin enxerga tudo independente do perfil" do
      admin = build(:admin_user, :admin, profile: profile_with("own"))
      expect(admin.scope_for(:leads)).to eq("all")
      expect(admin.owns_all?(:leads)).to be(true)
    end
  end

  describe "#team_scope_ids" do
    it "inclui o próprio usuário + toda a subárvore de gestão (recursivo)" do
      diretor   = create(:admin_user)
      gerente   = create(:admin_user, manager: diretor)
      corretor1 = create(:admin_user, manager: gerente)
      corretor2 = create(:admin_user, manager: gerente)
      outro     = create(:admin_user) # fora da árvore

      expect(diretor.team_scope_ids).to match_array(
        [diretor.id, gerente.id, corretor1.id, corretor2.id]
      )
      expect(gerente.team_scope_ids).to match_array([gerente.id, corretor1.id, corretor2.id])
      expect(corretor1.team_scope_ids).to eq([corretor1.id])
      expect(diretor.team_scope_ids).not_to include(outro.id)
    end
  end
end
