require "rails_helper"

RSpec.describe "Brokers", type: :request do
  before { host! "localhost" }

  it "exibe apenas corretores marcados para aparecer no site" do
    broker_profile = Tenant.default.profiles.find_by!(key: "agent")
    visible = create(:admin_user, name: "Corretor Visível", profile: broker_profile, active: true, display_on_site: true)
    hidden = create(:admin_user, name: "Corretor Oculto", profile: broker_profile, active: true, display_on_site: false)

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

  describe "página do corretor" do
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

  def create_broker(name, **attrs)
    broker_profile = tenant.profiles.find_by!(key: "agent")
    create(:admin_user, tenant: tenant, name: name, profile: broker_profile,
      active: true, display_on_site: true, **attrs)
  end

  def tenant
    Tenant.default
  end
end
