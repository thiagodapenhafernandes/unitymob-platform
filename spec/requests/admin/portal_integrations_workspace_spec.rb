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
    expect(response.body).to include("Enviar imóveis", "Receber leads")
    document = Nokogiri::HTML(response.body)
    publication = document.at_css('section[aria-label="Envio de imóveis aos portais"]')
    reception = document.at_css('section[aria-label="Recebimento de leads do portal"]')
    expect(publication.at_css('input[name="portal_integration[enabled]"]')).to be_present
    expect(publication.at_css('input[name="portal_integration[leads_enabled]"]')).to be_nil
    expect(reception.at_css('input[name="portal_integration[leads_enabled]"]')).to be_present
    expect(reception.at_css('select[name="portal_integration[allowed_statuses][]"]')).to be_nil
    expect(response.body).to include("URL do Feed para o portal")
    expect(response.body).to include("Últimos retornos do portal")
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('.portal-integrations-nav__link[aria-current="page"]')).to be_present
    expect(document.css(".ax-operational-panel").size).to be >= 3
    expect(document.at_css(".ax-collapse-card #webhookSection[hidden]")).to be_nil
    expect(response.body).not_to include("Token do Feed", "Webhook Secret", "Testar feed completo", "Visualizar amostra")
    expect(document.at_css(".ax-form-actions--static")).to be_present
    expect(document.at_css("table.ax-table caption")).to be_nil
    expect(document.css('table.ax-table th[scope="col"]').size).to eq(5)
    expect(document.at_css(".portal-integrations-empty-cell .ax-empty-state--compact")).to be_present
    expect(response.body).not_to include("Como ativar este portal")
    expect(response.body).not_to include("Checklist de configuração")
    expect(response.body).not_to include("Resumo do Feed")
  end


  it "exibe a URL na aba de leads mesmo enquanto a conexão está pendente" do
    allow(Portal::LeadGatewayClient).to receive(:gateway_url).and_return("https://webhooks.example.com")
    allow(Portal::LeadGatewayClient).to receive(:configured?).and_return(false)
    integration = PortalIntegration.for_portal!("zapimoveis", tenant: admin.tenant)
    get admin_portal_integrations_path(portal: "zapimoveis")
    document = Nokogiri::HTML(response.body)
    inputs = document.css('#portal-leads input[aria-label="URL de recebimento de leads"]')
    expect(inputs.size).to eq(1)
    expect(inputs.first["value"]).to eq("https://webhooks.example.com/webhooks/grupozap/#{integration.lead_route_key}")
    expect(response.body).to include("A conexão precisa ser habilitada pelo suporte")
  end

  it "gera e exibe a URL pública para uma integração antiga sem configuração interna" do
    allow(Portal::LeadGatewayClient).to receive(:gateway_url).and_return("")
    allow(Portal::LeadGatewayClient).to receive(:configured?).and_return(false)
    integration = PortalIntegration.for_portal!("zapimoveis", tenant: admin.tenant)
    integration.update_column(:lead_route_key, nil)
    get admin_portal_integrations_path(portal: "zapimoveis")
    expect(integration.reload.lead_route_key).to be_present
    url = "https://webhooks.unitymob.com.br/webhooks/grupozap/#{integration.lead_route_key}"
    expect(response.body).to include(url)
    get admin_portal_integrations_path(portal: "zapimoveis")
    expect(integration.reload.lead_webhook_url).to eq(url)
  end

  it "agrupa os portais e preserva a URL existente ao alternar o feed" do
    integration = PortalIntegration.for_portal!("zapimoveis", tenant: admin.tenant)
    url = integration.lead_webhook_url
    get admin_portal_integrations_path(portal: "vivareal_vrsync")
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.css('.portal-integrations-nav__link').map(&:text).join).to include("Grupo OLX")
    expect(document.css('.portal-integrations-nav__link').size).to eq(PortalIntegration::PORTALS.size - 1)
    expect(document.at_css('#portal-leads input[aria-label="URL de recebimento de leads"]')["value"]).to eq(url)
    expect(document.at_css('#portal-leads form')["action"]).to eq(admin_portal_integration_path("zapimoveis"))
    expect(document.at_css('#portal-publication form')["action"]).to eq(admin_portal_integration_path("vivareal_vrsync"))
    expect(integration.reload.lead_webhook_url).to eq(url)
  end

  it "mantém os feeds Imovelweb separados da integração de leads OLX" do
    %w[imovelweb imovelweb_2].each do |portal|
      get admin_portal_integrations_path(portal: portal)
      expect(response).to have_http_status(:ok)
      document = Nokogiri::HTML(response.body)
      expect(document.at_css('#portal-leads')).to be_nil
      expect(document.at_css('#portal-publication form')["action"]).to eq(admin_portal_integration_path(portal))
      expect(response.body).to include("URL do Feed para o portal")
    end
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
    expect(response.body).to include("Receber leads do Grupo OLX")
    expect(response.body).to include("Último lead recebido")

    get admin_portal_integrations_path(portal: "chavesnamao")

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Receber leads do Grupo OLX")
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
    expect(response.body).not_to include("Chave do CRM — Grupo OLX")
    expect(response.body).to include("Receber leads")
    expect(response.body).not_to include("chave-secreta-123")

    get admin_portal_integrations_path(portal: "chavesnamao")

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Chave do CRM — Grupo OLX")
  end

  it "impede o administrador da conta de alterar a chave global do CRM" do
    post grupozap_key_admin_portal_integrations_path,
         params: { portal: "vivareal_vrsync", grupozap_secret_key: "nova-chave-456" }

    expect(response).to have_http_status(:forbidden)
    expect(Setting.get(PortalIntegration::GRUPOZAP_SECRET_KEY)).not_to eq("nova-chave-456")
  end

  it "preserva as credenciais automáticas e de suporte ao salvar a configuração da conta" do
    integration = PortalIntegration.for_portal!("zapimoveis", tenant: admin.tenant)
    integration.update!(webhook_secret: "support-secret")
    token = integration.feed_token
    patch admin_portal_integration_path("zapimoveis"), params: {
      portal_integration: { enabled: "1", feed_token: "changed-token", webhook_secret: "changed-secret" }
    }
    expect(response).to redirect_to(admin_portal_integrations_path(portal: "zapimoveis"))
    expect(integration.reload.feed_token).to eq(token)
    expect(integration.webhook_secret).to eq("support-secret")
    expect(integration).to be_enabled
  end

  it "mantém a amostra do feed restrita ao suporte" do
    get preview_feed_admin_portal_integration_path("zapimoveis")
    expect(response).to have_http_status(:forbidden)
  end

  it "salva o recebimento sem alterar os filtros de publicação" do
    integration = PortalIntegration.for_portal!("zapimoveis", tenant: admin.tenant)
    integration.update!(enabled: true, allowed_business_types: ["aluguel"])
    patch admin_portal_integration_path("zapimoveis"), params: { portal_integration: { leads_enabled: "1" } }
    expect(response).to redirect_to(admin_portal_integrations_path(portal: "zapimoveis"))
    expect(integration.reload.allowed_business_types).to eq(["aluguel"])
    expect(integration).to be_leads_receiving
  end
end

RSpec.describe "Abas de configuração dos portais", type: :request do
  include Devise::Test::IntegrationHelpers

  it "salva a identificação na conta atual, preserva a publicação e retorna à aba de leads" do
    admin = create(:admin_user, :admin)
    host! "localhost"
    sign_in admin
    integration = PortalIntegration.for_portal!("zapimoveis", tenant: admin.tenant)
    integration.update!(allowed_business_types: ["aluguel"])
    other = Tenant.create!(name: "Conta externa", slug: "portal-externo-#{SecureRandom.hex(4)}")
    foreign = PortalIntegration.for_portal!("zapimoveis", tenant: other)
    patch admin_portal_integration_path("zapimoveis"), params: {
      section: "leads", portal_integration: { account_id: "987654", leads_enabled: "1" }
    }
    expect(response).to redirect_to(admin_portal_integrations_path(portal: "zapimoveis", anchor: "portal-leads"))
    expect(integration.reload.account_id).to eq("987654")
    expect(integration.allowed_business_types).to eq(["aluguel"])
    expect(foreign.reload.account_id).not_to eq("987654")
    get admin_portal_integrations_path(portal: "zapimoveis")
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('.ax-studio-nav--underline')).to be_present
    expect(document.at_css('label[for="lead_advertiser_account_id"]')).to be_present
    expect(document.at_css('#portal-leads input[name="portal_integration[account_id]"]')['value']).to eq("987654")
  end
end
