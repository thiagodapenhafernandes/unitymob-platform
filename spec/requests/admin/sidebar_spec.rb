require "rails_helper"

RSpec.describe "Admin sidebar", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  it "exibe menus administrativos recomendados para administrador" do
    admin = create(:admin_user, :admin)
    sign_in admin

    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Administração")
    expect(response.body).to include("Segurança")
    expect(response.body).to include("Segurança de Acesso")
    expect(response.body).to include("Configurações de Campo")
    expect(response.body).to include("Auditorias")
    expect(response.body).to include("Auditoria de Campo")
    expect(response.body).to include("Auditoria de Acessos")
    expect(response.body).to include("Auditoria de Exportações")
    expect(response.body).to include("Redirecionamentos SEO")
    expect(response.body).to include("Trackeamento")
    expect(response.body).to include(admin_access_security_path)
    expect(response.body).to include(edit_admin_field_settings_path)
    expect(response.body).to include(admin_field_audit_logs_path)
    expect(response.body).to include(admin_access_audit_logs_path)
    expect(response.body).to include(admin_data_export_audit_logs_path)
    expect(response.body).to include(admin_seo_redirects_path)
    expect(response.body).to include(admin_tracking_integration_path)
  end

  it "direciona o menu Imóveis para a aba Todos" do
    admin = create(:admin_user, :admin)
    sign_in admin

    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(CGI.escapeHTML(admin_habitations_path(ownership: "all")))
  end

  it "mantém corretor fora de integrações e dashboard de captação no menu" do
    broker_profile = Profile.create!(
      name: "Corretor #{SecureRandom.hex(6)}",
      permissions: Profile.default_permissions_for("Corretor")
    )
    broker = create(:admin_user, profile: broker_profile)
    sign_in broker

    get admin_habitations_path(ownership: "all")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Captações")
    expect(response.body).not_to include("Dashboard Captação")
    expect(response.body).not_to include("Integrações")
    expect(response.body).not_to include(admin_webhook_settings_path)
    expect(response.body).not_to include(dashboard_admin_captacoes_path)
  end
end
