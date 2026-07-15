require "rails_helper"

RSpec.describe "Admin::Habitations conteúdo IA x corretor", type: :request do
  include Devise::Test::IntegrationHelpers

  def agent_profile
    Tenant.default.profiles.find_by!(key: "agent").tap do |p|
      p.update!(permissions: Profile.default_permissions_for("Corretor"))
    end
  end

  before { host! "localhost" }

  it "bloqueia 'Gerar com IA' para o corretor e libera para o admin" do
    agent = create(:admin_user, email: "agent-ai-#{SecureRandom.hex(6)}@salute.test")
    agent.update!(profile: agent_profile)
    habitation = create(:habitation, admin_user: agent, exibir_no_site_flag: true,
                        codigo: "AI-#{SecureRandom.hex(4)}")

    sign_in agent
    post generate_ai_preview_admin_habitation_path(habitation)
    expect(response).to redirect_to(edit_admin_habitation_path(habitation.id, anchor: "features"))
    expect(flash[:alert]).to include("restrita ao administrador")

    admin = create(:admin_user, :admin, email: "admin-ai-#{SecureRandom.hex(6)}@salute.test")
    sign_in admin
    post generate_ai_preview_admin_habitation_path(habitation)
    # admin passa pelo guard; sem token OpenAI cai no aviso de configurar, NÃO no de restrição
    expect(flash[:alert].to_s).not_to include("restrita ao administrador")
  end
end
