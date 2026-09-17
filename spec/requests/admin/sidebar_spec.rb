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

  it "mostra Início apontando para o PWA no primeiro item do menu do corretor" do
    tenant = Tenant.default
    broker_profile = tenant.profiles.find_by!(key: "agent")
    broker_profile.update!(permissions: Profile.default_permissions_for("Corretor"))
    broker = create(:admin_user, tenant: tenant, profile: broker_profile, field_agent_enabled: true)
    sign_in broker

    get admin_habitations_path(ownership: "all"), headers: { "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Mobile" }

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    product_items = html.css('.ax-nav__section[data-nav-section="product"] .ax-nav__section-items a.ax-nav__link')
    home_link = product_items.find { |link| link.text.squish == "Início" }

    expect(home_link).to be_present
    expect(product_items.first.text.squish).to eq("Início")
    expect(home_link["href"]).to eq(field_root_path)
    expect(product_items.map { |link| link.text.squish }).not_to include("Painel")
  end

  it "respeita a ordem dos menus definida no perfil efetivo" do
    tenant = Tenant.create!(name: "Tenant menu order #{SecureRandom.hex(3)}", slug: "tenant-menu-order-#{SecureRandom.hex(3)}")
    profile = Profile.create!(
      tenant: tenant,
      name: "Produto ordenado #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 600,
      permissions: {
        Profile::MENU_ORDER_PERMISSION_KEY => { "product" => %w[leads dashboard imoveis lead_pool lead_funnels] },
        "dashboard" => { "view" => true },
        "leads" => { "view" => true, "scope" => "all" },
        "imoveis" => { "view" => true, "scope" => "all" },
        "lead_pool" => { "view" => true, "scope" => "all" },
        "lead_funnels" => { "view" => true, "scope" => "all" }
      }
    )
    user = create(:admin_user, tenant: tenant, profile: profile, role: :editor)
    sign_in user

    get admin_root_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    product_items = html.css('.ax-nav__section[data-nav-section="product"] .ax-nav__section-items a.ax-nav__link')
    expect(product_items.map { |link| link.text.squish }.first(3)).to eq(%w[Leads Painel Imóveis])
  end

  it "herda a ordem do perfil vertical quando a funcao horizontal nao define ordem propria" do
    tenant = Tenant.create!(name: "Tenant menu vertical #{SecureRandom.hex(3)}", slug: "tenant-menu-vertical-#{SecureRandom.hex(3)}")
    vertical = Profile.create!(
      tenant: tenant,
      name: "Vertical ordenado #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 600,
      permissions: {
        Profile::MENU_ORDER_PERMISSION_KEY => { "product" => %w[leads dashboard imoveis lead_pool lead_funnels] },
        "dashboard" => { "view" => true },
        "leads" => { "view" => true, "scope" => "all" },
        "imoveis" => { "view" => true, "scope" => "all" },
        "lead_pool" => { "view" => true, "scope" => "all" },
        "lead_funnels" => { "view" => true, "scope" => "all" }
      }
    )
    horizontal = Profile.create!(
      tenant: tenant,
      name: "Funcao sem ordem #{SecureRandom.hex(3)}",
      axis: "horizontal",
      vertical_profile: vertical,
      permissions: {}
    )
    user = create(:admin_user, tenant: tenant, profile: vertical, horizontal_profile: horizontal, role: :editor)
    sign_in user

    get admin_root_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    product_items = html.css('.ax-nav__section[data-nav-section="product"] .ax-nav__section-items a.ax-nav__link')
    expect(product_items.map { |link| link.text.squish }.first(3)).to eq(%w[Leads Painel Imóveis])
  end

  it "prioriza a ordem da funcao horizontal quando ela define ordem propria" do
    tenant = Tenant.create!(name: "Tenant menu horizontal #{SecureRandom.hex(3)}", slug: "tenant-menu-horizontal-#{SecureRandom.hex(3)}")
    vertical = Profile.create!(
      tenant: tenant,
      name: "Vertical com ordem #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 600,
      permissions: {
        Profile::MENU_ORDER_PERMISSION_KEY => { "product" => %w[leads dashboard imoveis] },
        "dashboard" => { "view" => true },
        "leads" => { "view" => true, "scope" => "all" },
        "imoveis" => { "view" => true, "scope" => "all" }
      }
    )
    horizontal = Profile.create!(
      tenant: tenant,
      name: "Funcao com ordem #{SecureRandom.hex(3)}",
      axis: "horizontal",
      vertical_profile: vertical,
      permissions: {
        Profile::MENU_ORDER_PERMISSION_KEY => { "product" => %w[imoveis dashboard leads] }
      }
    )
    user = create(:admin_user, tenant: tenant, profile: vertical, horizontal_profile: horizontal, role: :editor)
    sign_in user

    get admin_root_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    product_items = html.css('.ax-nav__section[data-nav-section="product"] .ax-nav__section-items a.ax-nav__link')
    expect(product_items.map { |link| link.text.squish }.first(3)).to eq(["Imóveis", "Painel", "Leads"])
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
        "conta" => { "manage" => true },
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
    expect(response.body).to include(admin_profiles_path)
  end

  it "trava seções sensíveis quando o perfil não tem a chave da seção" do
    tenant = Tenant.create!(name: "Tenant section lock #{SecureRandom.hex(3)}", slug: "tenant-section-lock-#{SecureRandom.hex(3)}")
    profile = Profile.create!(
      tenant: tenant,
      name: "Gestão interna #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 600,
      permissions: {
        "dashboard" => { "view" => true },
        "marketing" => { "manage" => true }
      }
    )
    user = create(:admin_user, tenant: tenant, profile: profile, role: :editor)
    sign_in user

    get admin_root_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('.ax-nav__section[data-nav-section="growth"]')).to be_present
    expect(html.at_css('.ax-nav__section[data-nav-section="public-site"]')).to be_nil
    expect(html.at_css('.ax-nav__section[data-nav-section="integrations"]')).to be_nil
    expect(html.at_css('.ax-nav__section[data-nav-section="settings"]')).to be_nil
    expect(html.at_css('.ax-nav__section[data-nav-section="account"]')).to be_nil

    get admin_seo_dashboard_path
    expect(response).to redirect_to(admin_root_path)

    get admin_attribute_options_path
    expect(response).to redirect_to(admin_root_path)

    get admin_account_settings_path
    expect(response).to redirect_to(admin_root_path)

    get admin_profiles_path
    expect(response).to redirect_to(admin_root_path)
  end

  it "usa a função horizontal para travar seções de um admin da conta" do
    tenant = Tenant.create!(name: "Tenant horizontal lock #{SecureRandom.hex(3)}", slug: "tenant-horizontal-lock-#{SecureRandom.hex(3)}")
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    internal_management = Profile.create!(
      tenant: tenant,
      name: "Gestão Interna #{SecureRandom.hex(3)}",
      axis: "horizontal",
      vertical_profile: owner_profile,
      position: 100,
      permissions: {
        "dashboard" => { "view" => true },
        "marketing" => { "manage" => true },
        "agenda_fotografia" => { "view" => true, "manage" => true },
        "inbound_webhooks" => { "manage" => true },
        "site_publico" => { "manage" => false },
        "integracoes" => { "manage" => false },
        "configuracoes" => { "manage" => false },
        "conta" => { "manage" => false }
      }
    )
    user = create(:admin_user, :admin, tenant: tenant, profile: owner_profile, horizontal_profile: internal_management)
    sign_in user

    get admin_root_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css('.ax-nav__section[data-nav-section="growth"]')).to be_present
    expect(html.at_css('.ax-nav__section[data-nav-section="public-site"]')).to be_nil
    expect(html.at_css('.ax-nav__section[data-nav-section="integrations"]')).to be_nil
    expect(html.at_css('.ax-nav__section[data-nav-section="settings"]')).to be_nil
    expect(html.at_css('.ax-nav__section[data-nav-section="account"]')).to be_nil

    get admin_seo_dashboard_path
    expect(response).to redirect_to(admin_root_path)

    get admin_portal_integrations_path
    expect(response).to redirect_to(admin_root_path)

    get admin_scheduling_integration_path
    expect(response).to redirect_to(admin_root_path)

    get admin_webhook_settings_path
    expect(response).to redirect_to(admin_root_path)

    get admin_attribute_options_path
    expect(response).to redirect_to(admin_root_path)

    get admin_account_settings_path
    expect(response).to redirect_to(admin_root_path)
  end

  it "respeita a trava granular horizontal quando a seção macro está liberada" do
    tenant = Tenant.create!(name: "Tenant granular lock #{SecureRandom.hex(3)}", slug: "tenant-granular-lock-#{SecureRandom.hex(3)}")
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    horizontal = Profile.create!(
      tenant: tenant,
      name: "Admin sem segurança #{SecureRandom.hex(3)}",
      axis: "horizontal",
      vertical_profile: owner_profile,
      position: 110,
      permissions: {
        "dashboard" => { "view" => true },
        "conta" => { "manage" => true },
        "access_security" => { "manage" => false, "scope" => "all" },
        "field_audit" => { "view" => false, "scope" => "all" },
        "access_audit" => { "view" => false, "scope" => "all" },
        "data_export_audit" => { "view" => false, "scope" => "all" }
      }
    )
    user = create(:admin_user, :admin, tenant: tenant, profile: owner_profile, horizontal_profile: horizontal)
    sign_in user

    get admin_root_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    account = html.at_css('.ax-nav__section[data-nav-section="account"]')
    expect(account).to be_present
    expect(account.text).not_to include("Segurança de Acesso")
    expect(account.to_html).not_to include(admin_field_audit_logs_path)
    expect(account.to_html).not_to include(admin_access_audit_logs_path)
    expect(account.to_html).not_to include(admin_data_export_audit_logs_path)
    expect(user.can?(:manage, :conta)).to be(true)
    expect(user.can?(:manage, :access_security)).to be(false)

    get admin_access_security_path
    expect(response).to redirect_to(admin_root_path)

    get admin_field_audit_logs_path
    expect(response).to redirect_to(admin_root_path)

    get admin_access_audit_logs_path
    expect(response).to redirect_to(admin_root_path)

    get admin_data_export_audit_logs_path
    expect(response).to redirect_to(admin_root_path)

    patch admin_trusted_device_path(1), params: { status: "trusted" }
    expect(response).to redirect_to(admin_root_path)
  end

  it "filtra os submenus de funil pela permissão granular do tipo" do
    tenant = Tenant.create!(name: "Tenant funnel sidebar #{SecureRandom.hex(3)}", slug: "tenant-funnel-sidebar-#{SecureRandom.hex(3)}")
    rental_pipeline = create(:lead_pipeline, tenant: tenant, name: "Locação", kind: "rental", position: 1)
    sale_pipeline = create(:lead_pipeline, tenant: tenant, name: "Vendas", kind: "sale", position: 2)
    profile = Profile.create!(
      tenant: tenant,
      name: "Operador Locação #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 600,
      permissions: {
        "dashboard" => { "view" => true },
        "leads" => { "view" => true, "scope" => "all" },
        "lead_funnels" => { "view" => true },
        "lead_funnel_rental" => { "view" => true },
        "lead_funnel_sale" => { "view" => false }
      }
    )
    user = create(:admin_user, tenant: tenant, profile: profile, role: :editor)
    sign_in user

    get admin_root_path

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    product = html.at_css('.ax-nav__section[data-nav-section="product"]')
    expect(product.to_html).to include(admin_lead_pipeline_leads_path(rental_pipeline, view: "kanban"))
    expect(product.to_html).not_to include(admin_lead_pipeline_leads_path(sale_pipeline, view: "kanban"))

    get admin_lead_pipeline_leads_path(sale_pipeline, view: "kanban")
    expect(response).to redirect_to(admin_root_path)
  end

  it "exibe atendimento WhatsApp para perfil autorizado somente no inbox" do
    tenant = Tenant.create!(name: "Tenant inbox sidebar #{SecureRandom.hex(3)}", slug: "tenant-inbox-sidebar-#{SecureRandom.hex(3)}")
    profile = Profile.create!(
      tenant: tenant,
      name: "Atendente WhatsApp #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 600,
      permissions: {
        "whatsapp_inbox" => { "view" => true, "manage" => true, "scope" => "own" }
      }
    )
    user = create(:admin_user, tenant: tenant, profile: profile, role: :editor)
    sign_in user

    get admin_whatsapp_conversations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(admin_whatsapp_conversations_path)
    expect(response.body).to include("Atendimento")
    expect(response.body).not_to include(admin_whatsapp_campaigns_path)
    expect(response.body).not_to include(admin_whatsapp_templates_path)
  end

  it "mantém Admin do Sistema sem links diretos para áreas operacionais de tenants" do
    system_admin = create(:admin_user, super_admin: true)
    sign_in system_admin

    get admin_system_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Painel do Sistema")
    expect(response.body).to include("Acesse áreas operacionais apenas por impersonação.")
    expect(response.body).to include(admin_system_path)
    expect(response.body).to include(admin_system_health_path)
    expect(response.body).to include(admin_system_error_events_path)
    expect(response.body).not_to include(admin_tracking_integration_path)
    expect(response.body).not_to include(admin_storage_integration_path)
    expect(response.body).not_to include(CGI.escapeHTML(admin_habitations_path(ownership: "all")))
    expect(response.body).not_to include(admin_leads_path)
    expect(response.body).not_to include(admin_whatsapp_campaigns_path)
    expect(response.body).not_to include(admin_admin_users_path)
  end
end
