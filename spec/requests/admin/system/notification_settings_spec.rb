require "rails_helper"

RSpec.describe "Admin::System::NotificationSettings", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  let(:profile_owner) { Tenant.default.profiles.find_by!(key: "tenant_owner") }

  it "redireciona usuário não autenticado" do
    get edit_admin_system_notification_settings_path
    expect(response).to have_http_status(:redirect)
  end

  it "bloqueia o dono de conta que NÃO é admin do sistema" do
    owner = create(:admin_user, profile: profile_owner, super_admin: false)
    sign_in owner, scope: :admin_user

    get edit_admin_system_notification_settings_path
    expect(response).to redirect_to(admin_root_path)
    expect(flash[:alert]).to match(/Admin do Sistema/i)
  end

  it "renderiza a tela para o admin do sistema (tolerante pré-migration)" do
    sys = create(:admin_user, super_admin: true)
    sign_in sys, scope: :admin_user

    get edit_admin_system_notification_settings_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Notificações globais")
    # Sempre há SMTP global (EmailSetting) e Push (PushSetting) — logo o card de
    # transportes globais aparece independentemente do SystemNotificationSetting.
    expect(response.body).to include("Transportes globais")
  end
end
