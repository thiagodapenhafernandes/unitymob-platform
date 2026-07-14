require "rails_helper"

RSpec.describe "Admin::PresentationAuditLogs workspace", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "presentation-audit-#{SecureRandom.hex(5)}@salute.test") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza metricas, filtros e historico com contratos compartilhados" do
    get admin_presentation_audit_logs_path

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css(".ax-workspace-heading")).to be_present
    expect(document.css(".ax-metric-card").size).to eq(4)
    expect(document.at_css('section.ax-filter-form[role="search"][aria-label="Filtros da auditoria de apresentações"]')).to be_present
    expect(document.at_css(".ax-operational-panel")).to be_present
    expect(document.at_css("table.ax-table caption").text).to include("Envios de cartões de apresentação")
    expect(document.css('table.ax-table th[scope="col"]').size).to eq(5)
    expect(document.at_css("table.ax-table .ax-empty-state--compact")).to be_present
  end

  it "nao oferece usuarios de outro tenant no filtro" do
    other_tenant = Tenant.create!(name: "Outra auditoria #{SecureRandom.hex(3)}", slug: "outra-auditoria-#{SecureRandom.hex(4)}")
    other_profile = other_tenant.profiles.find_by!(key: "agent")
    foreign_user = create(:admin_user, tenant: other_tenant, profile: other_profile, name: "Corretor externo #{SecureRandom.hex(3)}")

    get admin_presentation_audit_logs_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(foreign_user.name)
  end

  it "bloqueia acesso direto sem permissao de auditoria" do
    profile = Profile.create!(
      tenant: admin.tenant,
      name: "Sem auditoria #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 7_700,
      permissions: {}
    )
    viewer = create(:admin_user, tenant: admin.tenant, profile: profile, role: :editor)
    sign_out admin
    sign_in viewer

    get admin_presentation_audit_logs_path

    expect(response).to redirect_to(admin_root_path)
  end
end
