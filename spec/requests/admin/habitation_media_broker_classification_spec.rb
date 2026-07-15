require "rails_helper"

RSpec.describe "Admin::HabitationMedia classificação x corretor", type: :request do
  include Devise::Test::IntegrationHelpers

  def agent_profile
    Tenant.default.profiles.find_by!(key: "agent").tap do |profile|
      profile.update!(permissions: Profile.default_permissions_for("Corretor"))
    end
  end

  before do
    host! "localhost"
    allow_any_instance_of(Admin::HabitationMediaController).to receive(:verify_authenticity_token)
  end

  it "não deixa o corretor alterar a classificação das fotos, mas o admin deixa" do
    agent = create(:admin_user, email: "agent-cls-#{SecureRandom.hex(6)}@salute.test")
    agent.update!(profile: agent_profile)
    habitation = create(:habitation, admin_user: agent, foto_classificacao: "Boas",
                        codigo: "9#{SecureRandom.random_number(10**10)}")

    sign_in agent
    patch admin_habitation_media_path(habitation), params: { habitation: { foto_classificacao: "Amadoras" } }
    expect(habitation.reload.foto_classificacao).to eq("Boas")

    admin = create(:admin_user, :admin, email: "admin-cls-#{SecureRandom.hex(6)}@salute.test")
    sign_in admin
    patch admin_habitation_media_path(habitation), params: { habitation: { foto_classificacao: "Profissionais" } }
    expect(habitation.reload.foto_classificacao).to eq("Profissionais")
  end
end
