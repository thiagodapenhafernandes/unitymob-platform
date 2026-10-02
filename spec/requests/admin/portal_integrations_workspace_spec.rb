require "rails_helper"

RSpec.describe "Admin::PortalIntegrations workspace", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "prioriza navegação, configuração, feed e retornos sem blocos explicativos duplicados" do
    get admin_portal_integrations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("portal-integrations-nav")
    expect(response.body).to include("portal-integrations-commandbar")
    expect(response.body).to include("Configuração")
    expect(response.body).to include("URL do Feed para o portal")
    expect(response.body).to include("Últimos retornos do portal")
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('.portal-integrations-nav__link[aria-current="page"]')).to be_present
    expect(document.css(".ax-operational-panel").size).to be >= 3
    expect(document.at_css(".ax-collapse-card #webhookSection[hidden]")).to be_present
    expect(document.at_css(".ax-form-actions--static")).to be_present
    expect(document.at_css("table.ax-table caption").text).to include("Últimos eventos recebidos")
    expect(document.css('table.ax-table th[scope="col"]').size).to eq(5)
    expect(document.at_css(".portal-integrations-empty-cell .ax-empty-state--compact")).to be_present
    expect(response.body).not_to include("Como ativar este portal")
    expect(response.body).not_to include("Checklist de configuração")
    expect(response.body).not_to include("Resumo do Feed")
  end


  it "isola os retornos recebidos por tenant" do
    own_code = "PORTAL-#{SecureRandom.hex(3)}"
    foreign_code = "FORA-#{SecureRandom.hex(3)}"
    other_tenant = Tenant.create!(name: "Portal externo #{SecureRandom.hex(3)}", slug: "portal-externo-#{SecureRandom.hex(4)}")
    PortalListingState.create!(tenant: admin.tenant, portal: PortalIntegration::PORTALS.first, habitation_code: own_code, last_event_type: "updated", last_received_at: Time.current)
    PortalListingState.create!(tenant: other_tenant, portal: PortalIntegration::PORTALS.first, habitation_code: foreign_code, last_event_type: "updated", last_received_at: Time.current)

    get admin_portal_integrations_path(portal: PortalIntegration::PORTALS.first)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(own_code)
    expect(response.body).not_to include(foreign_code)
  end

  it "bloqueia acesso direto para usuario que nao e dono da conta" do
    profile = admin.tenant.profiles.find_by!(key: "agent")
    viewer = create(:admin_user, tenant: admin.tenant, profile: profile, role: :editor)
    sign_out admin
    sign_in viewer

    get admin_portal_integrations_path

    expect(response).to redirect_to(admin_root_path)
  end

  it "mostra o interruptor de leads só nos portais Grupo OLX" do
    get admin_portal_integrations_path(portal: "zapimoveis")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Receber leads deste portal")
    expect(response.body).to include("Último lead recebido")

    get admin_portal_integrations_path(portal: "chavesnamao")

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Receber leads deste portal")
  end

  it "liga o recebimento de leads do portal" do
    patch admin_portal_integration_path("zapimoveis"),
          params: { portal_integration: { enabled: "1", leads_enabled: "1", account_id: "42" } }

    expect(response).to redirect_to(admin_portal_integrations_path(portal: "zapimoveis"))
    integration = PortalIntegration.find_by!(tenant: admin.tenant, portal: "zapimoveis")
    expect(integration).to be_leads_receiving
  end

  it "mostra o cartão da chave do CRM só nos portais Grupo OLX, sem exibir o valor" do
    Setting.set(PortalIntegration::GRUPOZAP_SECRET_KEY, "chave-secreta-123", tenant: nil)

    get admin_portal_integrations_path(portal: "zapimoveis")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Chave do CRM — Grupo OLX")
    expect(response.body).to include("Configurada")
    expect(response.body).not_to include("chave-secreta-123")

    get admin_portal_integrations_path(portal: "chavesnamao")

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Chave do CRM — Grupo OLX")
  end

  it "salva a chave do CRM global e rejeita em branco" do
    post grupozap_key_admin_portal_integrations_path,
         params: { portal: "vivareal_vrsync", grupozap_secret_key: "nova-chave-456" }

    expect(response).to redirect_to(admin_portal_integrations_path(portal: "vivareal_vrsync"))
    expect(Setting.get(PortalIntegration::GRUPOZAP_SECRET_KEY)).to eq("nova-chave-456")

    post grupozap_key_admin_portal_integrations_path,
         params: { portal: "vivareal_vrsync", grupozap_secret_key: "  " }

    expect(response).to redirect_to(admin_portal_integrations_path(portal: "vivareal_vrsync"))
    expect(Setting.get(PortalIntegration::GRUPOZAP_SECRET_KEY)).to eq("nova-chave-456")
  end
end
