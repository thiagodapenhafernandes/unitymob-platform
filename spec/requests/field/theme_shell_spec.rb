require "rails_helper"

RSpec.describe "Field theme shell", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:mobile_headers) { { "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Mobile" } }
  let(:broker) { create(:admin_user, :field_agent) }

  before do
    host! "localhost"
    sign_in broker
  end

  it "usa a identidade primária do tenant no modo claro da pessoa" do
    broker.update!(admin_theme_mode: "light")
    broker.tenant.update!(name: "Conexão Imobiliária", slug: "conexao-imobiliaria-#{SecureRandom.hex(3)}")
    LayoutSetting.instance(tenant: broker.tenant).update!(site_name: "Conexão Imobiliária", admin_primary_color: "#3E6F9E")
    other_tenant = Tenant.create!(name: "Outro Field", slug: "outro-field-#{SecureRandom.hex(3)}")
    LayoutSetting.instance(tenant: other_tenant).update!(site_name: "Salute Imóveis", admin_primary_color: "#DC2626")

    get field_root_path, headers: mobile_headers

    document = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(document.at_css("title").text).to eq("Conexão Imobiliária — Campo")
    expect(document.at_css('meta[name="apple-mobile-web-app-title"]')["content"]).to eq("Conexão Imobiliária Campo")
    expect(document.at_css('link[rel="manifest"]')["href"]).to eq("/field/manifest?tenant=#{broker.tenant.slug}")
    expect(document.at_css('link[rel="apple-touch-icon"]')["href"]).to include("/pwa-icon-192?tenant=#{broker.tenant.slug}&v=")
    expect(document.at_css("html")["data-field-theme"]).to eq("light")
    expect(document.css('meta[name="theme-color"]').size).to eq(1)
    expect(document.at_css('meta[name="theme-color"]')["content"]).to eq("#3E6F9E")
    expect(response.body).to include("--field-primary: #3E6F9E")
    expect(response.body).not_to include("Salute Campo", "Salute Imóveis — Campo", "#DC2626", "#0d6efd", "#0a58ca")
  end

  it "aplica o modo escuro da pessoa sem consumir o modo legado do tenant" do
    broker.update!(admin_theme_mode: "dark")
    LayoutSetting.instance(tenant: broker.tenant).update!(
      admin_theme_mode: "light",
      admin_primary_color: "#3E6F9E"
    )

    get field_root_path, headers: mobile_headers

    document = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(document.at_css("html")["data-field-theme"]).to eq("dark")
    expect(document.at_css('meta[name="theme-color"]')["content"]).to eq(LayoutSetting::ADMIN_DARK_THEME[:header])
    expect(response.body).to include("--field-primary: #3E6F9E", "ax-user-menu--compact", 'aria-checked="true"')
    expect(document.css('.field-theme-toggle, .field-logout')).to be_empty
    expect(document.at_css('.ax-user-menu a[href="/admin/my_profile/edit"]')).to be_present
    expect(response.body).to include('data-controller="theme-preference"', 'submit-&gt;theme-preference#submit')
  end

  it "oferece chamados no menu e carrega a janela de abertura" do
    Support::Account.create!(uid: SecureRandom.uuid, local_tenant_id: broker.tenant_id, name: "Conta", endpoint: "https://central.example.test", secret: "s" * 64)
    get field_root_path, headers: mobile_headers
    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('.ax-user-menu [data-support-new-url]')).to be_present
    expect(document.at_css('#support-modal')).to be_present
    expect(document.at_css('script[src*="support_desk"]')).to be_present
  end

  it "mantem a busca inteligente coberta pelo tema escuro do PWA" do
    stylesheet = Rails.root.join("app/assets/stylesheets/field_theme.css").read

    expect(stylesheet).to include(
      '[data-field-theme="dark"] :is(.field-ai-search__composer, .field-ai-search__confirmation)',
      '[data-field-theme="dark"] .field-ai-search__input',
      '[data-field-theme="dark"] .field-ai-property-card',
      '[data-field-theme="dark"] .field-ai-selection-bar',
      '[data-field-theme="dark"] .field-property-preview-modal'
    )
    expect(stylesheet).to include(
      "background: var(--field-surface);",
      "background: var(--field-surface-muted);",
      "color: var(--field-text);",
      "object-position: center center;",
      ".field-property-preview-modal"
    )
  end
end
