require "rails_helper"

RSpec.describe "Admin notification workspaces", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "notification-workspaces-#{SecureRandom.hex(6)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza a configuracao SMTP tenant-scoped no cabecalho compartilhado" do
    get edit_admin_email_setting_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-workspace-heading", "Meu SMTP", "Configurações · Notificações")
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('dl.ax-status-list[aria-label="Diagnóstico do canal de e-mail"]')).to be_present
    expect(document.at_css(".ax-form-actions--static")).to be_present
  end

  it "nao exibe a configuracao SMTP de outra conta" do
    other_tenant = Tenant.create!(name: "Conta SMTP externa #{SecureRandom.hex(3)}", slug: "smtp-externa-#{SecureRandom.hex(4)}")
    foreign_host = "smtp-fora-#{SecureRandom.hex(4)}.test"
    EmailSetting.create!(tenant: other_tenant, smtp_address: foreign_host)

    get edit_admin_email_setting_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(foreign_host)
  end

  it "bloqueia acesso direto ao SMTP sem permissao de integracoes" do
    profile = Profile.create!(
      tenant: admin.tenant,
      name: "Sem integrações #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 7_500,
      permissions: {}
    )
    viewer = create(:admin_user, tenant: admin.tenant, profile: profile, role: :editor)
    sign_out admin
    sign_in viewer

    get edit_admin_email_setting_path

    expect(response).to redirect_to(admin_root_path)
  end

  it "renderiza a politica do atendimento quando a integracao esta pronta" do
    create(:whatsapp_business_integration, connected_by_admin_user: admin, tenant: admin.tenant)

    get edit_admin_whatsapp_service_setting_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-workspace-heading", "Atendimento WhatsApp", "Configurações · Atendimento")
    expect(response.body).to include("presentation_enabled", "inbox_attendance_enabled")
  end
end
