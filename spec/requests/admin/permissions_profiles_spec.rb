require "rails_helper"

RSpec.describe "Admin profile permissions", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  it "bloqueia gerente de imprimir e exportar imóveis" do
    manager_profile = Profile.create!(
      name: "Gerente #{SecureRandom.hex(6)}",
      permissions: Profile.default_permissions_for("Gerente")
    )
    manager = create(:admin_user, profile: manager_profile)

    sign_in manager

    post export_admin_habitations_path
    expect(response).to redirect_to(admin_habitations_path)

    get exports_admin_habitations_path
    expect(response).to redirect_to(admin_habitations_path)

    get print_admin_habitations_path
    expect(response).to redirect_to(admin_habitations_path)
  end

  it "permite gerente editar pendência de revisão apenas do próprio time" do
    manager_profile = Profile.find_or_initialize_by(name: "Gerente")
    manager_profile.permissions = Profile.default_permissions_for("Gerente")
    manager_profile.active = true
    manager_profile.save!
    manager = create(:admin_user, profile: manager_profile, acting_type: :sales)
    team_broker = create(:admin_user, manager: manager, acting_type: :sales)
    outside_broker = create(:admin_user, acting_type: :sales)
    team_intake = create(:habitation, :broker_intake, admin_user: team_broker, intake_status: "submitted_for_admin_review")
    outside_intake = create(:habitation, :broker_intake, admin_user: outside_broker, intake_status: "submitted_for_admin_review")

    sign_in manager

    get edit_admin_habitation_path(team_intake)
    expect(response).to have_http_status(:ok)

    get edit_admin_habitation_path(outside_intake)
    expect(response).to redirect_to(admin_habitations_path)
  end

  it "bloqueia corretor de editar captação pendente de revisão" do
    broker_profile = Profile.create!(
      name: "Corretor #{SecureRandom.hex(6)}",
      permissions: Profile.default_permissions_for("Corretor")
    )
    broker = create(:admin_user, profile: broker_profile)
    intake = create(:habitation, :broker_intake, admin_user: broker, intake_status: "submitted_for_admin_review")

    sign_in broker

    get edit_admin_captacao_path(intake)
    expect(response).to redirect_to(admin_captacoes_path)

    get edit_admin_habitation_path(intake)
    expect(response).to redirect_to(admin_habitations_path)
  end

  it "controla se o corretor aparece no site pelo cadastro administrativo" do
    admin = create(:admin_user, :admin)
    broker_profile = Profile.create!(
      name: "Corretor #{SecureRandom.hex(6)}",
      permissions: Profile.default_permissions_for("Corretor")
    )
    broker = create(:admin_user, profile: broker_profile, display_on_site: true)

    sign_in admin

    get edit_admin_admin_user_path(broker)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Exibir perfil no site")

    patch admin_admin_user_path(broker), params: {
      admin_user: {
        name: broker.name,
        email: broker.email,
        profile_id: broker.profile_id,
        acting_type: broker.acting_type,
        active: "1",
        display_on_site: "0"
      }
    }

    expect(response).to redirect_to(admin_admin_users_path)
    expect(broker.reload.display_on_site).to be(false)
  end

  it "não concede integrações nem dashboard de captação ao perfil padrão de corretor" do
    permissions = Profile.default_permissions_for("Corretor")

    expect(permissions.dig("captacoes", "view")).to be(true)
    expect(permissions["captacao_dashboard"]).to be_nil
    expect(permissions["integracoes"]).to be_nil
  end

  it "bloqueia webhooks para corretor mesmo por URL direta" do
    broker_profile = Profile.create!(
      name: "Corretor #{SecureRandom.hex(6)}",
      permissions: Profile.default_permissions_for("Corretor")
    )
    broker = create(:admin_user, profile: broker_profile)

    sign_in broker

    get admin_webhook_settings_path

    expect(response).to redirect_to(admin_root_path)
  end
end
