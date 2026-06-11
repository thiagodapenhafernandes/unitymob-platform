require "rails_helper"

RSpec.describe "Admin impersonations", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  it "permite admin impersonar e voltar para a própria sessão" do
    admin = create(:admin_user, :admin, name: "Admin Original")
    broker_profile = Profile.create!(
      name: "Corretor #{SecureRandom.hex(6)}",
      permissions: Profile.default_permissions_for("Corretor")
    )
    broker = create(:admin_user, profile: broker_profile, name: "Corretor Impersonado")

    sign_in admin

    post impersonate_admin_admin_user_path(broker)

    expect(response).to redirect_to(admin_root_path)
    expect(session[:impersonator_admin_user_id]).to eq(admin.id)
    expect(AccessAuditLog.where(event_type: "impersonation_start", admin_user: broker)).to exist

    get admin_admin_users_path

    expect(response).to redirect_to(admin_root_path)

    delete admin_impersonation_path

    expect(response).to redirect_to(admin_admin_users_path)
    expect(session[:impersonator_admin_user_id]).to be_nil
    expect(AccessAuditLog.where(event_type: "impersonation_stop", admin_user: admin)).to exist

    get admin_admin_users_path

    expect(response).to have_http_status(:ok)
  end

  it "bloqueia usuário não-admin mesmo com permissão de gerenciar corretores" do
    profile = Profile.create!(
      name: "Gestor Corretores #{SecureRandom.hex(6)}",
      permissions: {
        "admin" => false,
        "dashboard" => { "view" => true },
        "corretores" => { "manage" => true }
      }
    )
    manager = create(:admin_user, profile: profile, name: "Gestor")
    broker = create(:admin_user, name: "Corretor Alvo")

    sign_in manager

    post impersonate_admin_admin_user_path(broker)

    expect(response).to redirect_to(admin_root_path)
    expect(session[:impersonator_admin_user_id]).to be_nil

    get admin_admin_users_path

    expect(response).to have_http_status(:ok)
  end
end
