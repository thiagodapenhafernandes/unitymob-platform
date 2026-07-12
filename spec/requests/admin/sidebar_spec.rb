require "rails_helper"

RSpec.describe "Admin sidebar", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  it "exibe menus administrativos recomendados para administrador" do
    admin = create(:admin_user, :admin)
    sign_in admin

    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Conta")
    expect(response.body).to include("Segurança")
    expect(response.body).to include("Segurança de Acesso")
    expect(response.body).to include("Configurações de Campo")
    expect(response.body).to include("Auditorias")
    expect(response.body).to include("Auditoria de Campo")
    expect(response.body).to include("Auditoria de Acessos")
    expect(response.body).to include("Auditoria de Exportações")
    expect(response.body).to include("Redirecionamentos SEO")
    expect(response.body).to include("Rastreamento")
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

  it "agrupa os itens dentro do li de cada seção do menu" do
    admin = create(:admin_user, :admin)
    sign_in admin

    get admin_root_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    product = html.at_css('.ax-nav__section[data-nav-section="product"]')
    product_items = product.at_xpath('./ul[contains(concat(" ", normalize-space(@class), " "), " ax-nav__section-items ")]')

    expect(product.at_xpath('./button[@aria-controls="nav-section-product"]')).to be_present
    expect(product_items.at_css('a[href*="/admin/habitations"]')).to be_present
    expect(product_items.at_css('a[href*="/admin/leads"]')).to be_present
    expect(html.css('.ax-nav--sectioned > li[data-nav-section] > .ax-nav__section-items')).not_to be_empty
    expect(html.at_css('.ax-nav--sectioned > li[data-nav-section] + li:not([data-nav-section])')).to be_nil
  end

  it "mantém corretor fora de integrações e dashboard de captação no menu" do
    tenant = Tenant.default
    broker_profile = tenant.profiles.find_by!(key: "agent")
    broker_profile.update!(permissions: Profile.default_permissions_for("Corretor"))
    broker = create(:admin_user, tenant: tenant, profile: broker_profile)
    sign_in broker

    get admin_habitations_path(ownership: "all")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Captações")
    expect(response.body).not_to include("Dashboard Captação")
    expect(response.body).not_to include("Integrações")
    expect(response.body).not_to include(admin_webhook_settings_path)
    expect(response.body).not_to include(dashboard_admin_captacoes_path)
  end

  it "marca Captações como ativo para o controller real e não deixa Produto aberto por padrão" do
    admin = create(:admin_user, :admin)
    sign_in admin

    get admin_captacoes_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    active_link = html.at_css('.ax-nav__section[data-nav-section="operation"] a.ax-nav__link.active')
    product_trigger = html.at_css('.ax-nav__section[data-nav-section="product"] > .ax-nav__section-trigger')

    expect(active_link&.text&.squish).to eq("Captações")
    expect(product_trigger["aria-expanded"]).to eq("false")
  end

  it "exibe listagens administrativas de WhatsApp para usuário operacional autorizado" do
    tenant = Tenant.create!(name: "Tenant sidebar #{SecureRandom.hex(3)}", slug: "tenant-sidebar-#{SecureRandom.hex(3)}")
    profile = Profile.create!(
      tenant: tenant,
      name: "Operador WhatsApp #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 600,
      permissions: {
        "whatsapp_campaigns" => { "view" => true, "scope" => "own" }
      }
    )
    user = create(:admin_user, tenant: tenant, profile: profile, role: :editor)
    sign_in user

    get admin_whatsapp_campaign_recipients_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Conta")
    expect(response.body).to include("Importados CSV")
    expect(response.body).to include("Descadastros WhatsApp")
    expect(response.body).to include(admin_whatsapp_campaign_recipients_path)
    expect(response.body).to include(admin_whatsapp_campaign_unsubscribes_path)
    expect(response.body).not_to include(admin_profiles_path)
  end

  it "mantém Admin do Sistema sem links diretos para áreas operacionais de tenants" do
    system_admin = create(:admin_user, super_admin: true)
    sign_in system_admin

    get admin_system_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Painel do Sistema")
    expect(response.body).to include("Acesse áreas operacionais apenas por impersonação.")
    expect(response.body).to include(admin_system_path)
    expect(response.body).not_to include(CGI.escapeHTML(admin_habitations_path(ownership: "all")))
    expect(response.body).not_to include(admin_leads_path)
    expect(response.body).not_to include(admin_whatsapp_campaigns_path)
    expect(response.body).not_to include(admin_admin_users_path)
  end
end
