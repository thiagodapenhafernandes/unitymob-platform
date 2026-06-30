require "rails_helper"

RSpec.describe AdminUser, "governança de dados por equipe", type: :model do
  def profile_with(scope, tenant: Tenant.default, position: nil)
    position ||= rand(100..9_800)
    Profile.create!(tenant: tenant,
                    name: "Perfil #{scope} #{SecureRandom.hex(3)}",
                    axis: "vertical",
                    position: position,
                    permissions: { "leads" => { "view" => true, "scope" => scope } })
  end

  describe "#scope_for / #can_view_team? / #owns_all?" do
    it "reflete o scope configurado no perfil" do
      own  = build(:admin_user, profile: profile_with("own", position: 1_100))
      team = build(:admin_user, profile: profile_with("team", position: 1_200))
      all  = build(:admin_user, profile: profile_with("all", position: 1_300))

      expect(own.scope_for(:leads)).to eq("own")
      expect(team.scope_for(:leads)).to eq("team")
      expect(all.scope_for(:leads)).to eq("all")

      expect(team.can_view_team?(:leads)).to be(true)
      expect(own.can_view_team?(:leads)).to be(false)
      expect(all.owns_all?(:leads)).to be(true)
    end

    it "admin enxerga tudo independente do perfil" do
      tenant = Tenant.default
      admin = build(:admin_user, :admin, tenant: tenant, profile: tenant.profiles.find_by!(key: "tenant_owner"))
      expect(admin.scope_for(:leads)).to eq("all")
      expect(admin.owns_all?(:leads)).to be(true)
    end
  end

  describe "#team_scope_ids" do
    it "inclui o próprio usuário + toda a subárvore de gestão (recursivo)" do
      tenant = Tenant.default
      director_profile = profile_with("team", tenant: tenant, position: 2_100)
      manager_profile = profile_with("team", tenant: tenant, position: 2_500)
      agent_profile = tenant.profiles.find_by!(key: "agent")

      diretor   = create(:admin_user, tenant: tenant, profile: director_profile)
      gerente   = create(:admin_user, tenant: tenant, profile: manager_profile, manager: diretor)
      corretor1 = create(:admin_user, tenant: tenant, profile: agent_profile, manager: gerente)
      corretor2 = create(:admin_user, tenant: tenant, profile: agent_profile, manager: gerente)
      outro     = create(:admin_user, tenant: tenant, profile: agent_profile) # fora da árvore

      expect(diretor.team_scope_ids).to match_array(
        [diretor.id, gerente.id, corretor1.id, corretor2.id]
      )
      expect(gerente.team_scope_ids).to match_array([gerente.id, corretor1.id, corretor2.id])
      expect(corretor1.team_scope_ids).to eq([corretor1.id])
      expect(diretor.team_scope_ids).not_to include(outro.id)
    end
  end
end
