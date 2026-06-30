require "rails_helper"

RSpec.describe "Admin impersonations", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  it "permite Admin do Sistema impersonar e voltar para a própria sessão" do
    system_admin = create(:admin_user, super_admin: true, name: "Admin Sistema Original")
    tenant = Tenant.create!(name: "Tenant impersonation #{SecureRandom.hex(3)}", slug: "tenant-impersonation-#{SecureRandom.hex(3)}")
    broker_profile = tenant.profiles.find_by!(key: "agent")
    broker_profile.update!(permissions: Profile.default_permissions_for("Corretor"))
    broker = create(:admin_user, tenant: tenant, profile: broker_profile, name: "Corretor Impersonado")

    sign_in system_admin, scope: :admin_user

    post admin_system_user_impersonation_path(broker)

    expect(response).to redirect_to(admin_root_path)
    expect(session[:impersonator_admin_user_id]).to eq(system_admin.id)
    expect(AccessAuditLog.where(event_type: "impersonation_start", admin_user: broker)).to exist

    get admin_admin_users_path

    expect(response).to redirect_to(admin_root_path)

    delete admin_impersonation_path

    expect(response).to redirect_to(admin_system_users_path)
    expect(session[:impersonator_admin_user_id]).to be_nil
    expect(AccessAuditLog.where(event_type: "impersonation_stop", admin_user: system_admin)).to exist

    get admin_system_users_path

    expect(response).to have_http_status(:ok)
  end

  it "remove o endpoint operacional de impersonação de usuários da conta" do
    profile = Profile.create!(
      tenant: Tenant.default,
      name: "Gestor Corretores #{SecureRandom.hex(6)}",
      position: 600,
      permissions: {
        "admin" => false,
        "dashboard" => { "view" => true },
        "corretores" => { "manage" => true }
      }
    )
    manager = create(:admin_user, profile: profile, name: "Gestor")
    broker = create(:admin_user, name: "Corretor Alvo")

    sign_in manager

    post "/admin/admin_users/#{broker.id}/impersonate"

    expect(response).to have_http_status(:not_found)
    expect(session[:impersonator_admin_user_id]).to be_nil
    expect(AccessAuditLog.where(event_type: "impersonation_start", admin_user: broker)).not_to exist
  end
end
