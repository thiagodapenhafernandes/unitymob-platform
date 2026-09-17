require "rails_helper"

RSpec.describe "Admin::AccountSettings", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "account-settings-#{SecureRandom.hex(6)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza o hub permitido no cabecalho compartilhado" do
    get admin_account_settings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-workspace-heading", "Configurações da Conta", "Conta · Governança")
  end

  it "usa conta:manage para expor e executar governança da conta" do
    tenant = Tenant.create!(name: "Tenant governança #{SecureRandom.hex(3)}", slug: "tenant-governanca-#{SecureRandom.hex(3)}")
    profile = Profile.create!(
      tenant: tenant,
      name: "Governança da conta #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 8_750,
      permissions: {
        "dashboard" => { "view" => true },
        "conta" => { "manage" => true }
      }
    )
    user = create(:admin_user, tenant: tenant, profile: profile, role: :editor)

    sign_out admin
    sign_in user

    get admin_account_settings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Nome interno da conta")
    expect(response.body).to include("Perfis de acesso")
    expect(response.body).to include("Operacional")
    expect(response.body).to include(admin_profiles_path)
    expect(response.body).to include(admin_user_activity_sessions_path)

    patch admin_account_settings_path, params: { tenant: { name: "Conta Governada" } }

    expect(response).to redirect_to(admin_account_settings_path)
    expect(tenant.reload.name).to eq("Conta Governada")

    get admin_profiles_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Perfis de acesso")

    get admin_user_activity_sessions_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Auditoria operacional")
  end
end
