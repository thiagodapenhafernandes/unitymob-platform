require "rails_helper"

# Layouts do hero da home (Clássico, Barra, Cartão): cada um é um componente com a identidade de cada tema.
RSpec.describe "Layouts do hero", type: :request do
  let(:tenant) { Tenant.default }
  let(:home_setting) { HomeSetting.instance(tenant:) }

  before do
    host! "localhost"
    Tenants::LocalPublicHostOverride.clear!
    Rails.cache.clear
  end

  after { Tenants::LocalPublicHostOverride.clear! }

  def html = Nokogiri::HTML(response.body)

  def enable_ai!(voice: false)
    Setting.set(Ai::PropertyContentService::API_KEY_SETTING, "token", "Token", tenant:)
    PropertySetting.instance(tenant:).update!(ai_property_search_enabled: true, voice_property_search_enabled: voice)
  end

  Tenant::PUBLIC_SITE_THEMES.each do |theme_key, theme|
    variant = theme[:variant].presence || "default"

    context "tema #{theme_key} (variante #{variant})" do
      before { tenant.update_columns(public_site_theme: theme_key) }

      it "Barra: título, abas, campos, busca livre e filtro detalhado, com a posição escolhida" do
        home_setting.update!(hero_layout: "bar", hero_search_align: "left", hero_title: "Título da barra")

        get root_path

        expect(response).to have_http_status(:ok)
        root = html.at_css("section.public-theme-hero-bar.public-theme-hero-bar--#{variant}")
        expect(root).to be_present
        expect(root["class"]).to include("is-align-left")
        expect(root.at_css("h1").text.strip).to eq("Título da barra")
        expect(html.css("h1").size).to eq(1)
        form = root.at_css("form.public-theme-hero-bar__form[action='/imoveis']")
        expect(form.css("button.public-theme-hero-bar__tab").map(&:text)).to eq(%w[Comprar Alugar])
        # localização, tipo e dormitórios usam o combobox (autocomplete) dos filtros públicos
        expect(form.css(".public-theme-combobox[data-controller='combobox']").size).to eq(3)
        expect(form.at_css("input[type='hidden'][name='city[]']")).to be_present
        expect(form.at_css("input[type='hidden'][name='category[]']")).to be_present
        expect(form.at_css("input[type='hidden'][name='min_bedrooms']")).to be_present
        expect(form.at_css("input#hero_bar_bedrooms").ancestors(".public-theme-combobox").first["data-combobox-single-value"]).to eq("true")
        expect(form.css("#hero_bar_bedrooms_panel .public-theme-combobox__option").map { |node| node["data-value"] }).to eq(%w[1 2 3 4])
        expect(form.css("select")).to be_empty
        expect(form.at_css("input[name='search']")).to be_present
        expect(form.at_css("input[name='transaction_type'][value='venda']")).to be_present
        expect(root.at_css(".public-theme-hero-bar__detail")).to be_present
        # o "Filtro detalhado" abre o drawer global: ele existe na home com a Barra mesmo sem o botão flutuante
        expect(html.at_css("[data-controller='filter-drawer'] .public-theme-filter-drawer--#{variant}")).to be_present
        expect(html.at_css(".public-theme-filter-fab")).to be_nil
      end

      it "Cartão: abas, título, filtros, atalhos e busca rápida; sem IA não mostra o modo de descrição" do
        home_setting.update!(hero_layout: "card", hero_search_align: "right", hero_title: "Título do cartão", hero_ai_search_enabled: true)

        get root_path

        root = html.at_css("section.public-theme-hero-card.public-theme-hero-card--#{variant}")
        expect(root["class"]).to include("is-align-right")
        expect(root.at_css("h1.public-theme-hero-card__title").text.strip).to eq("Título do cartão")
        expect(html.css("h1").size).to eq(1)
        expect(root.css(".public-theme-hero-card__chip-option input").size).to eq(6)
        expect(root.at_css("input[name='search']")).to be_present
        expect(root.at_css("[data-hero-search-target='aiPanel']")).to be_nil # ligado na Home, mas a IA da conta não está pronta
      end

      it "Cartão com a IA da conta pronta: botão de voz antes de Comprar e barra de gravação com sugestões" do
        enable_ai!(voice: true)
        home_setting.update!(hero_layout: "card", hero_ai_search_enabled: true, hero_ai_suggestions: "Apto 2 quartos\nCasa com quintal\n\nStudio mobiliado\nQuarta frase")

        get root_path

        root = html.at_css(".public-theme-hero-card--#{variant}")
        tabs = root.at_css(".public-theme-hero-card__tabs")
        expect(tabs.element_children.first["data-hero-search-target"]).to eq("voiceToggle")
        expect(tabs.element_children.drop(1).map(&:text)).to eq(%w[Comprar Alugar])
        voice = root.at_css(".public-theme-hero-voice--#{variant}[data-hero-search-target='aiPanel'][hidden]")
        expect(voice).to be_present
        expect(voice["data-state"]).to eq("idle")
        expect(voice.css(".public-theme-hero-voice__suggestion").map { |node| node.text.strip }).to eq(["Apto 2 quartos", "Casa com quintal", "Studio mobiliado"])
        expect(voice.at_css("canvas[data-hero-search-target='wave']")).to be_present
        expect(voice.at_css("button[data-hero-search-target='action']")).to be_present
        expect(root.at_css("[data-controller='hero-search']")["data-hero-search-voice-value"]).to eq("true")
        expect(root.at_css("[data-hero-search-ai-url-value='/busca-ia']")).to be_present
        expect(root.at_css("[data-hero-search-target='filtersPanel']")).to be_present
      end

      it "Sem microfone na conta, a barra de voz vira só texto (sem onda sonora)" do
        enable_ai!(voice: false)
        home_setting.update!(hero_layout: "card", hero_ai_search_enabled: true)

        get root_path

        voice = html.at_css(".public-theme-hero-voice--#{variant}")
        expect(voice["data-state"]).to eq("text")
        expect(voice.at_css("canvas")).to be_nil
        expect(html.at_css(".public-theme-hero-voice__toggle").text).to include("Descrever")
      end

      it "Clássico segue sendo o hero de sempre, sem botão de voz por padrão" do
        get root_path

        expect(html.css(".public-theme-hero-bar, .public-theme-hero-card")).to be_empty
        expect(html.at_css("section#hero, section#top")).to be_present
        expect(html.at_css(".public-theme-hero-voice__toggle")).to be_nil
      end

      it "Clássico com a busca por voz ligada: botão antes de Comprar e painel que troca o filtro" do
        enable_ai!(voice: true)
        home_setting.update!(hero_layout: "classic", hero_ai_search_enabled: true, hero_ai_suggestions: "Apto 2 quartos")

        get root_path

        toggle = html.at_css("button.public-theme-hero-voice__toggle")
        expect(toggle).to be_present
        expect(toggle["data-action"]).to include("hero-search#toggleVoice")
        expect(toggle["aria-pressed"]).to eq("false")
        expect(html.at_css(".public-theme-hero-voice--#{variant}[data-hero-search-target='aiPanel'][hidden]")).to be_present
        expect(html.at_css("[data-controller~='hero-search'] [data-hero-search-target='filtersPanel']")).to be_present
        expect(html.at_css("[data-hero-search-ai-url-value='/busca-ia']")).to be_present
        expect(html.at_css(".public-theme-hero-voice__send")).to be_present
        expect(html.at_css(".public-theme-hero-voice canvas[data-hero-search-target='wave']")).to be_present
        # primeiro botão do grupo de finalidade (antes de Comprar)
        group = toggle.parent
        expect(group.element_children.first).to eq(toggle)
      end

      it "Barra com a busca por voz: botão no grupo de abas e painel dentro da barra; desligado, nada aparece" do
        enable_ai!(voice: true)
        home_setting.update!(hero_layout: "bar", hero_ai_search_enabled: true)

        get root_path

        bar = html.at_css(".public-theme-hero-bar--#{variant}")
        expect(bar.at_css(".public-theme-hero-bar__tabs").element_children.first["data-hero-search-target"]).to eq("voiceToggle")
        expect(bar.at_css(".public-theme-hero-voice--in-bar")).to be_present

        home_setting.update!(hero_ai_search_enabled: false)
        get root_path
        expect(html.at_css(".public-theme-hero-voice__toggle, .public-theme-hero-voice")).to be_nil
      end
    end
  end

  it "Barra com o botão flutuante só no celular: o drawer de filtros existe e não herda o 'só celular' (desktop abria nada)" do
    home_setting.update!(hero_layout: "bar", search_filter_display_mode: "hero", mobile_search_filter_display_mode: "floating")

    get root_path

    wrapper = html.at_css(".public-global-search[data-controller='filter-drawer']")
    expect(wrapper).to be_present
    expect(wrapper["class"]).not_to include("mobile-only") # a classe de aparelho vale só para o botão flutuante
    expect(wrapper.at_css(".public-theme-filter-drawer")).to be_present
    expect(wrapper.at_css(".public-global-search--mobile-only .public-theme-filter-fab")).to be_present
  end

  it "sem a IA ligada na Home o modo de descrição não aparece, mesmo com a conta pronta" do
    enable_ai!
    home_setting.update!(hero_layout: "card", hero_ai_search_enabled: false)

    get root_path

    expect(html.at_css("[data-hero-search-target='aiPanel']")).to be_nil
    expect(html.at_css(".public-theme-hero-voice__toggle")).to be_nil
  end
end
