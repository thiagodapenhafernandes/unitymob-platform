require "rails_helper"

RSpec.describe "Admin::ThemePreferences", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  it "permite que qualquer usuário altere somente o próprio tema" do
    user = create(:admin_user)
    other_user = create(:admin_user, tenant: user.tenant)
    sign_in user

    patch admin_theme_preference_path, params: { admin_user: { admin_theme_mode: "dark" } }

    expect(response).to redirect_to(admin_root_path)
    expect(user.reload.admin_theme_mode).to eq("dark")
    expect(other_user.reload.admin_theme_mode).to eq("light")
  end

  it "retorna a paleta efetiva para aplicar o tema sem recarregar a tela" do
    user = create(:admin_user)
    setting = LayoutSetting.instance(tenant: user.tenant)
    setting.update!(admin_primary_color: "#3E6F9E")
    sign_in user

    patch admin_theme_preference_path,
          params: { admin_user: { admin_theme_mode: "dark" } },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      "mode" => "dark",
      "theme_color" => LayoutSetting::ADMIN_DARK_THEME[:header],
      "tokens" => include(
        "admin_surface" => LayoutSetting::ADMIN_DARK_THEME[:surface],
        "admin_workspace_bg" => LayoutSetting::ADMIN_DARK_THEME[:workspace],
        "admin_primary" => "#3E6F9E",
        "admin_ink" => LayoutSetting::ADMIN_DARK_THEME[:ink]
      )
    )
  end

  it "mantém a preferência da identidade ao operar por um usuário espelho" do
    primary = create(:admin_user)
    mirror_tenant = Tenant.create!(name: "Conta espelho", slug: "conta-espelho-#{SecureRandom.hex(3)}")
    mirror_profile = mirror_tenant.profiles.find_by!(key: "agent")
    mirror = create(:admin_user, tenant: mirror_tenant, profile: mirror_profile, primary_admin_user: primary)
    inviter = create(:admin_user, :admin, tenant: mirror_tenant, profile: mirror_tenant.profiles.find_by!(key: "tenant_owner"))
    AccountMembership.create!(
      tenant: mirror_tenant,
      invited_email: primary.email,
      profile: mirror_profile,
      invited_by: inviter,
      primary_admin_user: primary,
      member_admin_user: mirror,
      status: :active,
      accepted_at: Time.current
    )
    sign_in mirror

    patch admin_theme_preference_path, params: { admin_user: { admin_theme_mode: "dark" } }

    expect(primary.reload.admin_theme_mode).to eq("dark")
    expect(mirror.reload.admin_theme_mode).to eq("light")
    expect(mirror.effective_admin_theme_mode).to eq("dark")
  end

  it "permite que o Admin do Sistema altere o próprio tema sem tenant" do
    system_admin = create(:admin_user, super_admin: true)
    sign_in system_admin

    patch admin_theme_preference_path, params: { admin_user: { admin_theme_mode: "dark" } }

    expect(response).to redirect_to(admin_root_path)
    expect(system_admin.reload.admin_theme_mode).to eq("dark")
    expect(Current.tenant).to be_nil
  end

  it "rejeita modos fora do contrato" do
    user = create(:admin_user)
    sign_in user

    patch admin_theme_preference_path, params: { admin_user: { admin_theme_mode: "tenant" } }

    expect(response).to redirect_to(admin_root_path)
    expect(user.reload.admin_theme_mode).to eq("light")
  end


  it "rejeita modo inválido também no contrato assíncrono" do
    user = create(:admin_user)
    sign_in user

    patch admin_theme_preference_path,
          params: { admin_user: { admin_theme_mode: "tenant" } },
          as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq("error" => "Tema de exibição inválido.")
    expect(user.reload.admin_theme_mode).to eq("light")
  end
end
