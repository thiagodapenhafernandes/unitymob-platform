require "rails_helper"

RSpec.describe "Public branding pages", type: :request do
  before do
    host! "localhost"
    Tenants::LocalPublicHostOverride.clear!
    tenant = Tenant.default
    LayoutSetting.instance(tenant: tenant).update!(site_name: "Marca Pública")
    ContactSetting.instance(tenant: tenant).update!(email_primary: "publico@example.com", phone: "(47) 3333-4444")
  end

  after do
    Tenants::LocalPublicHostOverride.clear!
  end

  it "renderiza as páginas institucionais com a identidade configurada" do
    [sobre_path, contato_path, parcerias_path, trabalhe_conosco_path, corporativos_path, privacy_policy_path, terms_of_use_path].each do |path|
      get path

      expect(response).to have_http_status(:ok), "esperava HTTP 200 em #{path}, recebeu #{response.status}"
    end

    get parcerias_path
    expect(response.body).to include("Marca Pública")
    expect(response.body).not_to include("Salute Parcerias")
  end

  it "mantém o endereço antigo de parcerias acessível" do
    get "/salute-parcerias"

    expect(response).to have_http_status(:ok)
  end

  it "publica somente os links úteis persistidos para o tenant" do
    tenant = Tenant.default
    expect(PublicSiteProfile.new({ useful_links: "Portal próprio|https://portal.example.com|Serviço do tenant|building" }, tenant: tenant).save).to be(true)

    get links_uteis_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Portal próprio")
    expect(response.body).to include("https://portal.example.com")
    expect(response.body).not_to include("balneariocamboriu.sc.gov.br")
  end

  it "renderiza o tema público inferido pela identidade do tenant com tokens de marca" do
    tenant = Tenant.default
    tenant.update!(name: "Conexão Imobiliária")
    LayoutSetting.instance(tenant: tenant).update!(
      primary_color: "#123456",
      secondary_color: "#234567",
      accent_color: "#A88932"
    )

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-public-site-theme="conexaoimobiliaria"')
    expect(response.body).to include("public_site_themes/conexaoimobiliaria")
    expect(response.body).to include("--color-primary: #123456")
    expect(response.body).to include("--color-secondary: #234567")
    expect(response.body).to include("--color-accent: #A88932")
  end

  it "renderiza blog somente quando configurado no tenant público" do
    ContactSetting.instance(tenant: Tenant.default).update!(blog_url: "https://blog.saluteimoveis.com")

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("https://blog.saluteimoveis.com")
  end

  it "aplica o CSS de header somente a partir da configuração da Home do tenant público" do
    HomeSetting.instance(tenant: Tenant.default).update!(
      public_header_css: "background-color: rgba(0,9,16,0.4);\nbackdrop-filter: blur(15px);"
    )

    get root_path

    expect(response).to have_http_status(:ok)
    header = Nokogiri::HTML(response.body).at_css("header[data-controller='navbar']")
    expect(header["style"]).to include("background-color: rgba(0,9,16,0.4);")
    expect(header["style"]).to include("backdrop-filter: blur(15px);")
  end

  it "não usa identidade pública da Salute quando o tenant ativo no dev não tem logo próprio" do
    tenant = Tenant.create!(name: "Conexão Imobiliária", slug: "conexao-imobiliaria-#{SecureRandom.hex(3)}")
    LayoutSetting.instance(tenant: tenant)
    ContactSetting.instance(tenant: tenant)
    FooterSetting.instance(tenant: tenant)
    HomeSetting.instance(tenant: tenant)
    Tenants::LocalPublicHostOverride.activate!(tenant)
    host! Tenants::LocalPublicHostOverride::HOST

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Conexão Imobiliária")
    expect(response.body).to include("Encontre o imóvel ideal com a Conexão Imobiliária.")
    expect(response.body).to include("public-site-hero-fallback")
    expect(response.body).not_to include("salute-imoveis.svg")
    expect(response.body).not_to include("blog.saluteimoveis.com")
    expect(response.body).not_to include("(47) 3311-1067")
    expect(response.body).not_to include("Compre ou alugue na imobiliária mais amada")
  end

  it "renderiza imóveis selecionados na Home somente a partir do tenant público" do
    Rails.cache.clear
    tenant = Tenant.default
    tenant.home_sections.destroy_all
    current_property = create(:habitation, tenant:, codigo: "HOME-CURRENT", titulo_anuncio: "Cobertura exclusiva do tenant atual")
    other_tenant = Tenant.create!(name: "Outro tenant público #{SecureRandom.hex(3)}", slug: "outro-publico-#{SecureRandom.hex(4)}")
    foreign_property = create(:habitation, tenant: other_tenant, codigo: "HOME-FOREIGN", titulo_anuncio: "Cobertura exclusiva de outro tenant")
    tenant.home_sections.create!(
      section_type: :featured_properties,
      title: "Curadoria manual",
      active: true,
      property_filters: { selected_property_ids: [foreign_property.id, current_property.id] }
    )

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Curadoria manual", "Cobertura exclusiva do tenant atual")
    expect(response.body).not_to include("Cobertura exclusiva de outro tenant")
  end
end
