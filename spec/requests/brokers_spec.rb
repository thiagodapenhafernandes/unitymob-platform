require "rails_helper"

RSpec.describe "Brokers", type: :request do
  include Devise::Test::IntegrationHelpers
  before { host! "localhost" }

  it "exibe apenas corretores marcados para aparecer no site" do
    broker_profile = Tenant.default.profiles.find_by!(key: "agent")
    visible = create(:admin_user, name: "Corretor Visível", profile: broker_profile, active: true, display_on_site: true)
    hidden = create(:admin_user, name: "Corretor Oculto", profile: broker_profile, active: true, display_on_site: false)
    attach_avatar(visible)
    attach_avatar(hidden)

    get brokers_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(visible.name)
    expect(response.body).not_to include(hidden.name)
  end

  it "exibe perfis verticais customizados abaixo do Tenant Owner sem depender do nome do cargo" do
    tenant = Tenant.default
    custom_profile = tenant.profiles.create!(
      name: "Consultor Especialista",
      axis: "vertical",
      position: 700,
      active: true,
      permissions: Profile.default_permissions_for("Corretor")
    )
    owner_profile = tenant.profiles.find_by!(key: "tenant_owner")
    visible_custom = create(:admin_user, tenant: tenant, name: "Consultor Público", profile: custom_profile, active: true, display_on_site: true)
    visible_owner = create(:admin_user, tenant: tenant, name: "Owner Não Público", profile: owner_profile, role: :admin, active: true, display_on_site: true)
    attach_avatar(visible_custom)
    attach_avatar(visible_owner)

    get brokers_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(visible_custom.name)
    expect(response.body).not_to include(visible_owner.name)
  end

  it "não exibe corretores de outro tenant no site público padrão" do
    default_tenant = Tenant.default
    other_tenant = Tenant.create!(name: "Outro #{SecureRandom.hex(3)}", slug: "outro-#{SecureRandom.hex(3)}")
    broker_profile = default_tenant.profiles.find_by!(key: "agent")
    other_profile = other_tenant.profiles.find_by!(key: "agent")

    visible = create(:admin_user, tenant: default_tenant, name: "Corretor Padrão", profile: broker_profile, active: true, display_on_site: true)
    other_visible = create(:admin_user, tenant: other_tenant, name: "Corretor Outro Tenant", profile: other_profile, active: true, display_on_site: true)
    attach_avatar(visible)
    attach_avatar(other_visible)

    get brokers_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(visible.name)
    expect(response.body).not_to include(other_visible.name)
  end

  it "monta link de WhatsApp sem duplicar DDI quando telefone já está normalizado" do
    broker_profile = Tenant.default.profiles.find_by!(key: "agent")
    broker = create(
      :admin_user,
      name: "Corretor WhatsApp",
      profile: broker_profile,
      active: true,
      display_on_site: true,
      phone: "5547999729441"
    )
    attach_avatar(broker)

    get brokers_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(broker.name)
    expect(response.body).to include("https://wa.me/5547999729441")
    expect(response.body).not_to include("https://wa.me/555547999729441")
  end

  it "shows Meu site button linking to the broker page, even without properties" do
    broker = create_broker("Abner Marcelo")

    get brokers_path

    expect(response.body).to include("Meu site")
    expect(response.body).to include('href="/abner-marcelo"')
  end

  it "não exibe corretor sem foto na vitrine" do
    with_photo = create_broker("Com Foto")
    without_photo = create_broker("Sem Foto", avatar: false)

    get brokers_path

    expect(response.body).to include(with_photo.name)
    expect(response.body).not_to include(without_photo.name)
  end

  describe "página do corretor" do
    Tenant::PUBLIC_SITE_THEMES.each_key do |theme|
      it "vincula links, captura e compartilhamento ao dono da página no tema #{theme}" do
        broker = create_broker("Dono da Pagina")
        property = create(:habitation, tenant: tenant, admin_user: broker)
        tenant.update_columns(public_site_theme: theme)

        get "/dono-da-pagina"
        expect(response).to have_http_status(:ok)
        link = HabitationShareLink.active.find_by!(habitation: property, admin_user: broker)
        html = Nokogiri::HTML(response.body)
        card = html.at_css("[data-property-id='#{property.id}']")
        urls = card.css("a[href]").map { |node| node["href"] }.select { |url| url.include?(property.slug) }
        urls << card["data-clickable-card-url-value"] if card["data-clickable-card-url-value"]
        expect(urls).to be_present
        expect(urls).to all(include("share_token=#{link.token}"))
        cta = card.at_css("button[data-share-token]")
        expect(cta["data-share-token"]).to eq(link.token)
        share_menu = card.at_css("[data-controller='broker-share']")
        if share_menu
          expect(share_menu["data-broker-share-fallback-url-value"]).to include("share_token=#{link.token}")
          expect(share_menu["data-broker-share-generate-url-value"]).to eq("")
        end

        get habitation_path(property, share_token: link.token)
        expect(response).to have_http_status(:ok)
        detail = Nokogiri::HTML(response.body)
        expect(detail.at_css(".public-habitations-show__broker-card").text).to include(broker.name)
        expect(detail.at_css("[data-controller='broker-share']")["data-broker-share-fallback-url-value"]).to include("share_token=#{link.token}")
      end
    end

    it "mantém os links comuns quando o corretor está logado" do
      broker = create_broker("Dono da Pagina")
      other = create_broker("Outro Corretor")
      property = create(:habitation, tenant: tenant, admin_user: broker)
      sign_in other
      get "/dono-da-pagina", headers: { "Turbo-Frame" => "public-listing-grid" }
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("share_token=broker-page-")
      expect(HabitationShareLink.where(habitation: property)).to be_empty
    end

    it "copia link comum para administrador do sistema sem conta, sem tentar gerar vínculo" do
      broker = create_broker("Dono da Pagina")
      property = create(:habitation, tenant: tenant, admin_user: broker)
      tenant.update_columns(public_site_theme: "conexaoimobiliaria")
      sign_in create(:admin_user, super_admin: true)
      get "/dono-da-pagina"
      expect(response).to have_http_status(:ok)
      menu = Nokogiri::HTML(response.body).at_css("[data-controller='broker-share']")
      expect(menu["data-broker-share-generate-url-value"]).to eq("")
      expect(menu["data-broker-share-fallback-url-value"]).to eq(habitation_url(property))
      expect(HabitationShareLink.where(habitation: property)).to be_empty
      post share_link_habitation_path(property), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["error"]).to include("vinculado a uma conta")
    end

    it "isola o cache entre páginas de corretores e a listagem genérica, renovando links expirados" do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      first = create_broker("Primeiro Corretor")
      second = create_broker("Segundo Corretor")
      property = create(:habitation, tenant: tenant, admin_user: first)
      HabitationBrokerAssignment.create!(habitation: property, admin_user: second, role: :captador)
      get "/primeiro-corretor"
      one = HabitationShareLink.active.find_by!(habitation: property, admin_user: first)
      get "/segundo-corretor"
      two = HabitationShareLink.active.find_by!(habitation: property, admin_user: second)
      expect(response.body).to include("share_token=#{two.token}")
      expect(response.body).not_to include("share_token=#{one.token}")
      get habitations_path
      expect(response.body).not_to include("share_token=#{one.token}", "share_token=#{two.token}")
      one.update!(expires_at: 1.minute.ago)
      get "/primeiro-corretor"
      expect(response.body).not_to include("share_token=#{one.token}")
      expect(HabitationShareLink.active.find_by!(habitation: property, admin_user: first).token).not_to eq(one.token)
    end

    it "lista apenas os imóveis do corretor com hero e filtros" do
      broker = create_broker("Abner Marcelo")
      other = create_broker("Ze Ninguem")
      create(:habitation, tenant: tenant, codigo: "ABNER-1", admin_user: broker)
      assigned = create(:habitation, tenant: tenant, codigo: "ABNER-2")
      HabitationBrokerAssignment.create!(habitation: assigned, admin_user: broker, role: :captador)
      create(:habitation, tenant: tenant, codigo: "ZE-1", admin_user: other)

      get "/abner-marcelo"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Abner Marcelo", "ABNER-1", "ABNER-2", "Buscar imóveis", "Ordenar:")
      expect(response.body).not_to include("ZE-1")
    end

    Tenant::PUBLIC_SITE_THEMES.each_key do |theme|
      it "usa título, descrição e foto do corretor no compartilhamento do tema #{theme}" do
        broker = create_broker("Daniele Bresolin", biography: "Atendimento personalizado para encontrar seu imóvel.")
        tenant.update_columns(public_site_theme: theme)
        get "/daniele-bresolin"
        expect(response).to have_http_status(:ok)
        html = Nokogiri::HTML(response.body)
        expect(html.at_css("title").text).to include("Daniele Bresolin")
        expect(html.at_css('meta[property="og:title"]')["content"]).to include("Daniele Bresolin")
        expect(html.at_css('meta[property="og:description"]')["content"]).to eq(broker.biography)
        expect(html.at_css('meta[name="description"]')["content"]).to eq(broker.biography)
        image = html.at_css('meta[property="og:image"]')["content"]
        expect(image).to include("/rails/active_storage/blobs/proxy/")
        expect(image).to start_with("http")
        expect(html.at_css('meta[property="og:image:alt"]')["content"]).to eq("Foto de Daniele Bresolin")
        expect(html.at_css('meta[property="og:url"]')["content"]).to end_with("/daniele-bresolin")
      end
    end

    it "renderiza unidade ligada a empreendimento (regressão do preload aninhado)" do
      broker = create_broker("Abner Marcelo")
      create(:habitation, tenant: tenant, codigo: "DEV-ABNER", tipo: "Empreendimento", status: "Venda")
      create(:habitation, tenant: tenant, codigo: "ABNER-UNIT", admin_user: broker,
        codigo_empreendimento: "DEV-ABNER")

      get "/abner-marcelo"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("ABNER-UNIT")
    end

    it "hero centralizado com foto, nome e contato, sem search" do
      create_broker("Abner Marcelo")

      get "/abner-marcelo"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        "public-theme-broker-hero__portrait",
        "public-theme-broker-hero__name",
        "Abner Marcelo",
        "public-theme-broker-hero__contact"
      )
      expect(response.body).not_to include(
        "public-theme-broker-hero__search",
        "public-theme-hero-bar__search",
        "public-theme-hero-card__panel",
        "public-theme-search__panel"
      )
      expect(response.body.scan(/<h1[\s>]/).size).to eq(1)
    end

    it "renderiza a foto do corretor sem crossorigin (redirect Spaces quebra com o atributo)" do
      broker = create_broker("Abner Marcelo")
      broker.avatar.attach(fixture_file_upload("spec/fixtures/files/watermark.png", "image/png"))

      get "/abner-marcelo"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("public-theme-broker-hero__portrait-img", "public-theme-broker-hero__bg-blur")
      hero_imgs = response.body.scan(/<img[^>]*public-theme-broker-hero__[^>]*>/)
      expect(hero_imgs.size).to eq(2)
      expect(hero_imgs.join).not_to include("crossorigin")
      expect(response.body).not_to include("public-theme-broker-hero__portrait-fallback")
    end

    it "usa o FAB + drawer global com submit no contexto do corretor, sem duplicar" do
      create_broker("Abner Marcelo")

      get "/abner-marcelo"

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("public-habitations-index__filterbar", "advanced-filters-form")
      expect(response.body).to include(
        "public-theme-filter-fab",
        "Filtrar imóveis",
        "public-global-search-drawer",
        "Buscar imóveis",
        'action="/abner-marcelo"'
      )
      expect(response.body.scan('id="public-global-search-drawer"').size).to eq(1)
    end

    it "mostra limpar filtros no cabeçalho quando há filtro ativo com resultados" do
      broker = create_broker("Abner Marcelo")
      create(:habitation, tenant: tenant, codigo: "ABNER-VENDA", admin_user: broker, status: "Venda",
        valor_venda_cents: 500_000_00, valor_locacao_cents: 0)
      create(:habitation, tenant: tenant, codigo: "ABNER-ALUGUEL", admin_user: broker, status: "Aluguel",
        valor_venda_cents: 0, valor_locacao_cents: 3_000_00)

      get "/abner-marcelo", params: { transaction_type: "aluguel" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("ABNER-ALUGUEL", "Limpar filtros")
      expect(response.body).to include('href="/abner-marcelo"')
    end

    it "renderiza o hero do corretor no tema luxury" do
      create_broker("Abner Marcelo")
      tenant.update_columns(public_site_theme: "salute_luxury")

      get "/abner-marcelo"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("public-theme-broker-hero--salute-luxury", "Abner Marcelo")
      expect(response.body).not_to include("public-theme-broker-hero__search")
    end

    it "filtra os imóveis dentro do contexto do corretor" do
      broker = create_broker("Abner Marcelo")
      create(:habitation, tenant: tenant, codigo: "ABNER-VENDA", admin_user: broker, status: "Venda",
        valor_venda_cents: 500_000_00, valor_locacao_cents: 0)
      create(:habitation, tenant: tenant, codigo: "ABNER-ALUGUEL", admin_user: broker, status: "Aluguel",
        valor_venda_cents: 0, valor_locacao_cents: 3_000_00)

      get "/abner-marcelo", params: { transaction_type: "aluguel" }

      expect(response.body).to include("ABNER-ALUGUEL")
      expect(response.body).not_to include("ABNER-VENDA")
    end

    it "mostra estado vazio com limpar filtros no contexto do corretor" do
      create_broker("Abner Marcelo")

      get "/abner-marcelo"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nenhum imóvel encontrado")
      expect(response.body).to include('href="/abner-marcelo"')
    end

    it "retorna 404 para corretor oculto do site" do
      create_broker("Oculto Silva", display_on_site: false)

      get "/oculto-silva"

      expect(response).to have_http_status(:not_found)
    end

    it "retorna 404 para corretor sem foto" do
      create_broker("Sem Foto", avatar: false)

      get "/sem-foto"

      expect(response).to have_http_status(:not_found)
    end

    it "retorna 404 para slug desconhecido" do
      get "/corretor-que-nao-existe"

      expect(response).to have_http_status(:not_found)
    end

    it "prioriza landing page sobre corretor no mesmo slug" do
      create_broker("Minha Pagina")
      LandingPage.create!(tenant: tenant, title: "Landing Original", slug: "minha-pagina", active: true)

      get "/minha-pagina"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Landing Original")
      expect(response.body).not_to include("Imóveis de Minha")
    end

    it "responde o frame da grade sem layout" do
      broker = create_broker("Abner Marcelo")
      create(:habitation, tenant: tenant, codigo: "ABNER-FRAME", admin_user: broker)

      get "/abner-marcelo", headers: { "Turbo-Frame" => "public-listing-grid" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("public-listing-grid", "ABNER-FRAME")
      expect(response.body).not_to include("<title>")
    end
  end

  def create_broker(name, avatar: true, **attrs)
    broker_profile = tenant.profiles.find_by!(key: "agent")
    broker = create(:admin_user, tenant: tenant, name: name, profile: broker_profile,
      active: true, display_on_site: true, **attrs)
    attach_avatar(broker) if avatar
    broker
  end

  def attach_avatar(broker)
    broker.avatar.attach(io: StringIO.new("foto"), filename: "foto.png", content_type: "image/png")
  end

  def tenant
    Tenant.default
  end
end
