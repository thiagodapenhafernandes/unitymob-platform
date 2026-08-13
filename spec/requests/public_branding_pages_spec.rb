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

  it "não exibe aviso específico de experiência personalizada na home" do
    LayoutSetting.instance.update!(
      interest_intelligence_enabled: true,
      interest_intelligence_settings: InterestIntelligence::Settings::DEFAULTS.merge(
        "requires_public_tracking_consent" => true
      )
    )

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Experiência personalizada")
  end

  it "informa na política de privacidade o uso de navegação para qualificar atendimento" do
    get privacy_policy_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("interações de navegação")
    expect(response.body).to include("qualificar o atendimento")
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

  it "prioriza os links rápidos cadastrados no rodapé sobre a lista automática" do
    footer_setting = FooterSetting.instance(tenant: Tenant.default)
    footer_setting.footer_links.create!(label: "Página institucional", url: "/sobre", position: 1)
    footer_setting.footer_links.create!(label: "Atendimento direto", url: "/contato", position: 2)

    allow(Footer::QuickLinksService).to receive(:call).and_return([
      Footer::QuickLinksService::Link.new(label: "Link automático", url: "/automatico")
    ])

    get root_path

    html = Nokogiri::HTML(response.body)
    footer_links = html.css("footer a").map { |link| [link.text.squish, link["href"]] }

    expect(response).to have_http_status(:ok)
    expect(footer_links).to include(["Página institucional", "/sobre"], ["Atendimento direto", "/contato"])
    expect(footer_links).not_to include(["Link automático", "/automatico"])
    expect(Footer::QuickLinksService).not_to have_received(:call)
  end

  it "usa os dados de contato como fallback no footer público" do
    tenant = Tenant.default
    FooterSetting.instance(tenant: tenant).update!(whatsapp: nil, email: nil)
    ContactSetting.instance(tenant: tenant).update!(
      whatsapp_primary: "(11) 99999-1111",
      whatsapp_secondary: "(11) 98888-2222",
      phone: "(11) 3000-3333",
      email_primary: "atendimento@example.com",
      facebook_url: "https://facebook.com/imobiliaria",
      instagram_url: "https://instagram.com/imobiliaria",
      youtube_url: "https://youtube.com/@imobiliaria",
      blog_url: "https://imobiliaria.example.com/blog",
      linkedin_url: "https://linkedin.com/company/imobiliaria"
    )

    get root_path

    html = Nokogiri::HTML(response.body)
    footer = html.at_css("footer")
    footer_hrefs = footer.css("a").map { |link| link["href"] }
    social_hrefs = footer.css("a[aria-label]").map { |link| link["href"] }

    expect(response).to have_http_status(:ok)
    expect(footer_hrefs).to include(
      "https://wa.me/5511999991111",
      "https://wa.me/5511988882222",
      "tel:+551130003333",
      "mailto:atendimento@example.com"
    )
    expect(footer.text).to include("atendimento@example.com")
    expect(social_hrefs).to include(
      "https://facebook.com/imobiliaria",
      "https://instagram.com/imobiliaria",
      "https://youtube.com/@imobiliaria",
      "https://imobiliaria.example.com/blog",
      "https://linkedin.com/company/imobiliaria"
    )
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

  it "oculta somente o telefone do header quando configurado" do
    tenant = Tenant.default
    ContactSetting.instance(tenant: tenant).update!(
      phone: "(47) 3515-4920",
      show_phone_in_header: false
    )

    get root_path

    html = Nokogiri::HTML(response.body)
    header = html.at_css("header[data-controller='navbar']")
    expect(response).to have_http_status(:ok)
    expect(header.text).not_to include("(47) 3515-4920")

    get privacy_policy_path

    html = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(html.text).to include("(47) 3515-4920")
  end

  it "renderiza CSS restrito para customização da logo pública" do
    layout_setting = LayoutSetting.instance(tenant: Tenant.default)
    layout_setting.logo.attach(
      io: StringIO.new(%(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 40"><text x="0" y="24">Logo</text></svg>)),
      filename: "logo.svg",
      content_type: "image/svg+xml"
    )
    layout_setting.update!(
      custom_logo_css: <<~CSS
        .custom-logo::after { content: "Prime"; display: block; }
        .custom-logo img { width: 210px; object-fit: contain; }
        body { display: none; }
      CSS
    )

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('class="custom-logo flex items-center"')
    expect(response.body).to include('id="custom-logo-css"')
    expect(response.body).to include('.custom-logo::after { content: "Prime"; display: block; }')
    expect(response.body).to include(".custom-logo img { width: 210px; object-fit: contain; }")
    expect(response.body).not_to include("body { display: none; }")
  end

  it "renderiza busca global por drawer quando desktop e mobile usam botão flutuante" do
    HomeSetting.instance(tenant: Tenant.default).update!(
      search_filter_display_mode: "floating",
      mobile_search_filter_display_mode: "floating"
    )

    get root_path

    html = Nokogiri::HTML(response.body)
    wrapper = html.at_css(".public-global-search")
    button = html.at_css(".public-global-search__button")
    drawer = html.at_css("#public-global-search-drawer")
    form = drawer.at_css("form")

    expect(response).to have_http_status(:ok)
    expect(html.at_css("#hero form")).to be_nil
    expect(wrapper["class"]).not_to include("public-global-search--desktop-only")
    expect(wrapper["class"]).not_to include("public-global-search--mobile-only")
    expect(button.text.squish).to eq("Filtrar imóveis")
    expect(button["data-action"]).to include("global-search-drawer#open")
    expect(drawer["aria-hidden"]).to eq("true")
    expect(form["action"]).to eq(habitations_path)
    expect(form["data-controller"]).to include("public-search-url")
    expect(form["data-action"]).to include("submit->public-search-url#submit")
    expect(form.at_css('input[name="transaction_type"]')["value"]).to eq("venda")
    search_field = form.at_css('.public-global-search__field--autocomplete input[name="search"]')
    expect(search_field).to be_present
    expect(search_field["data-action"]).to include("input->autocomplete#search")
    expect(form.at_css('[data-autocomplete-target="results"]')).to be_present
    expect(form.at_css('input[name="characteristics[]"][value="frente_mar"]')).to be_present
    expect(form.css('input[type="radio"][name="min_bedrooms"]').map { |input| input["value"] }).to eq(["1", "2", "3", "4", ""])
    expect(form.css('input[type="radio"][name="min_suites"]').map { |input| input["value"] }).to eq(["1", "2", "3", "4", ""])
    expect(form.css('input[type="radio"][name="min_parking"]').map { |input| input["value"] }).to eq(["1", "2", "3", "4", ""])
    expect(form.at_css(".public-global-search__highlights")).to be_present
    expect(form.at_css('input[name="characteristics[]"][value="opportunity"]')).to be_present
    expect(form.at_css('input[name="characteristics[]"][value="lancamento"]')).to be_present
    expect(form.at_css('input[name="characteristics[]"][value="na_planta"]')).to be_present
    expect(form.at_css('input[name="characteristics[]"][value="pronto"]')).to be_present
    expect(form.at_css(".public-global-search__features")).to be_present
    expect(form.text).to include("Características")
    expect(form.at_css('input[name="characteristics[]"][value="sacada"]')).to be_present
    expect(form.at_css('input[name="characteristics[]"][value="cozinha_gourmet_churrasqueira"]')).to be_present
    expect(form.at_css('input[name="characteristics[]"][value="piscina"]')).to be_present
    expect(form.at_css(".public-global-search__advanced")).not_to be_present
  end

  it "renderiza filtro no hero e oculta drawer quando configurado" do
    HomeSetting.instance(tenant: Tenant.default).update!(
      search_filter_display_mode: "hero",
      mobile_search_filter_display_mode: "hero"
    )

    get root_path

    html = Nokogiri::HTML(response.body)

    expect(response).to have_http_status(:ok)
    expect(html.at_css(".public-global-search__button")).to be_nil
    expect(html.at_css("#hero form")).to be_present
  end

  it "permite filtro no hero no desktop e botão flutuante somente no mobile" do
    HomeSetting.instance(tenant: Tenant.default).update!(
      search_filter_display_mode: "hero",
      mobile_search_filter_display_mode: "floating"
    )

    get root_path

    html = Nokogiri::HTML(response.body)
    hero_search = html.at_css("#hero .public-hero-search--desktop-only")
    drawer = html.at_css(".public-global-search")

    expect(response).to have_http_status(:ok)
    expect(hero_search.at_css("form")).to be_present
    expect(drawer["class"]).to include("public-global-search--mobile-only")
    expect(drawer.at_css(".public-global-search__button").text.squish).to eq("Filtrar imóveis")
  end

  it "permite filtro no hero e botão flutuante juntos no mobile" do
    HomeSetting.instance(tenant: Tenant.default).update!(
      search_filter_display_mode: "hero",
      mobile_search_filter_display_mode: "both"
    )

    get root_path

    html = Nokogiri::HTML(response.body)
    hero_search = html.at_css("#hero .relative.z-20")
    drawer = html.at_css(".public-global-search")

    expect(response).to have_http_status(:ok)
    expect(hero_search.at_css("form")).to be_present
    expect(hero_search["class"]).not_to include("public-hero-search--desktop-only")
    expect(hero_search["class"]).not_to include("public-hero-search--mobile-only")
    expect(drawer["class"]).to include("public-global-search--mobile-only")
    expect(drawer.at_css(".public-global-search__button").text.squish).to eq("Filtrar imóveis")
  end

  it "renderiza crédito global da Unitymob dentro do footer público" do
    get root_path

    html = Nokogiri::HTML(response.body)
    footer = html.at_css("footer")
    credit = footer.at_css(".public-unitymob-credit")
    link = credit.at_css('a[href="https://unitymob.com.br/"]')

    expect(response).to have_http_status(:ok)
    expect(footer).to be_present
    expect(credit.text.squish).to eq("Developed with care by Unitymob")
    expect(credit["class"]).to include("text-white/70")
    expect(credit["class"]).not_to include("bg-white")
    expect(link.text).to eq("Unitymob")
    expect(link["target"]).to eq("_blank")
    expect(link["rel"]).to include("noopener", "noreferrer")
    expect(link["style"]).to include("#65f4c7")
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
