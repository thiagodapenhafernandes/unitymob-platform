require "rails_helper"

# Página por blocos (construtor): o modo Vitrine precisa continuar servindo o propósito da landing de sempre
# (seleção de imóveis por filtros, ordem, paginação canônica) e agora também refina de verdade para o visitante.
RSpec.describe "Páginas por blocos", type: :request do
  let(:tenant) { Tenant.default }

  before { host! "localhost" }

  def page_with(blocks, **attrs)
    tenant.landing_pages.create!({ title: "Apartamentos", slug: "apartamentos", status: "published" }.merge(attrs)).tap do |page|
      blocks.each_with_index { |(type, data), index| page.blocks.create!(block_type: type, position: index + 1, data: data) }
    end
  end

  def html = Nokogiri::HTML(response.body)

  describe "vitrine (o modo que a landing sempre teve)" do
    let(:showcase) { ["property_showcase", { "filters" => { "category" => "Apartamento" } }] }

    it "ordena por preço e mantém os links de paginação canônicos do slug" do
      page = page_with([showcase])
      lower = create(:habitation, categoria: "Apartamento", titulo_anuncio: "Apartamento menor valor", valor_venda_cents: 500_000_00)
      higher = create(:habitation, categoria: "Apartamento", titulo_anuncio: "Apartamento maior valor", valor_venda_cents: 600_000_00)
      11.times { |index| create(:habitation, categoria: "Apartamento", titulo_anuncio: "Apartamento pagina #{index}", valor_venda_cents: 700_000_00 + index) }

      get public_landing_page_path(page.slug, sort: "price_asc")

      expect(response).to have_http_status(:ok)
      expect(response.body.index(lower.titulo_anuncio)).to be < response.body.index(higher.titulo_anuncio)
      expect(response.body).to include("/apartamentos?page=2&amp;sort=price_asc")
      expect(response.body).not_to include("/landing_pages/")
    end

    it "limita a seleção aos códigos escolhidos" do
      included = create(:habitation, codigo: "BL-1", titulo_anuncio: "Imóvel escolhido", exibir_no_site_flag: true)
      create(:habitation, codigo: "BL-2", titulo_anuncio: "Imóvel fora da seleção", exibir_no_site_flag: true)
      page = page_with([["property_showcase", { "filters" => { "property_codes" => [included.codigo] } }]])

      get public_landing_page_path(page.slug)

      expect(response.body).to include("Imóvel escolhido")
      expect(response.body).not_to include("Imóvel fora da seleção")
    end

    it "o visitante refina dentro da seleção da página, nunca amplia" do
      create(:habitation, categoria: "Apartamento", titulo_anuncio: "Apto no Centro", valor_venda_cents: 500_000_00)
      create(:habitation, categoria: "Casa", titulo_anuncio: "Casa fora da seleção", valor_venda_cents: 500_000_00)
      page = page_with([showcase])

      get public_landing_page_path(page.slug, category: ["Casa"])
      expect(response.body).not_to include("Casa fora da seleção") # a página só lista apartamentos, mesmo que o visitante peça casa
      expect(response.body).not_to include("Apto no Centro")        # e o refinamento "Casa" dentro de apartamentos não traz nada

      get public_landing_page_path(page.slug, category: ["Apartamento"])
      expect(response.body).to include("Apto no Centro")
    end

    it "mostra a barra de filtros, o drawer, a ordem e a contagem na vitrine interativa" do
      create(:habitation, categoria: "Apartamento", titulo_anuncio: "Um apartamento")
      page = page_with([showcase])

      get public_landing_page_path(page.slug)

      expect(html.at_css("[data-advanced-filters-target='sidebar']")).to be_present
      expect(html.at_css("form[action='/apartamentos']")).to be_present
      expect(html.at_css("select.public-theme-block-showcase__sort")).to be_present
      expect(html.at_css(".public-theme-block-showcase__count").text).to include("1 imóvel encontrado")
      expect(html.css("h1").size).to eq(1) # a vitrine abre a página com o H1 do título
    end

    it "vitrine sem filtros do visitante não tem barra, ordem nem paginação" do
      create(:habitation, categoria: "Apartamento", titulo_anuncio: "Um apartamento")
      page = page_with([["property_showcase", { "heading" => "Em destaque", "visitor_filters" => false, "filters" => { "category" => "Apartamento" } }]])

      get public_landing_page_path(page.slug)

      expect(html.at_css("[data-advanced-filters-target='sidebar']")).to be_nil
      expect(html.at_css("select.public-theme-block-showcase__sort")).to be_nil
      expect(html.at_css("h2.public-theme-block-showcase__title").text).to eq("Em destaque")
      expect(html.css("h1").size).to eq(1) # H1 vem do cabeçalho padrão da página
    end

    it "mostra o estado vazio quando nenhum imóvel atende" do
      page = page_with([showcase])

      get public_landing_page_path(page.slug)

      expect(html.at_css(".public-theme-block-showcase__empty").text).to include("Nenhum imóvel encontrado")
    end
  end

  describe "demais blocos" do
    it "texto sai sanitizado e botão #modal-ID mantém o gatilho global" do
      page = page_with([
        ["text", { "heading" => "Mais informações", "body" => '<p onclick="x()">Oi <strong>você</strong></p><script>alert(1)</script>' }],
        ["button", { "label" => "Fale conosco", "url" => "#modal-fale-conosco" }]
      ])

      get public_landing_page_path(page.slug)

      body = html.at_css(".public-theme-block-text__body")
      expect(body.css("script")).to be_empty
      expect(body.to_html).not_to include("onclick")
      expect(body.at_css("strong").text).to eq("você")
      expect(html.at_css("a.public-theme-block-button__link")["href"]).to eq("#modal-fale-conosco")
    end

    it "blocos ocultos não aparecem" do
      page = page_with([["text", { "heading" => "Visível" }], ["text", { "heading" => "Escondido" }]])
      page.blocks.last.update!(visible: false)

      get public_landing_page_path(page.slug)

      expect(response.body).to include("Visível")
      expect(response.body).not_to include("Escondido")
    end
  end

  describe "título e descrição do Google" do
    let(:page) { page_with([["text", { "heading" => "Oi" }]], title: "Título interno", slug: "seo-x", meta_title: "Título do Google", meta_description: "Descrição do Google") }

    def seo_tags
      { title: html.at_css("title").text.strip, description: html.at_css("meta[name='description']")["content"], og_title: html.at_css("meta[property='og:title']")["content"] }
    end

    it "usa o título e a descrição configurados na página" do
      get public_landing_page_path(page.slug)

      expect(seo_tags).to eq(title: "Título do Google", description: "Descrição do Google", og_title: "Título do Google")
    end

    it "o canonical é o endereço limpo da página (sem ?slug=)" do
      get public_landing_page_path(page.slug)

      expect(html.at_css("link[rel='canonical']")["href"]).to eq("http://localhost/#{page.slug}")
    end

    it "continua valendo depois de editar, mesmo com o SEO automático criado na primeira visita" do
      get public_landing_page_path(page.slug)
      page.update!(meta_title: "Novo título", meta_description: "Nova descrição")

      get public_landing_page_path(page.slug)

      expect(seo_tags).to include(title: "Novo título", description: "Nova descrição", og_title: "Novo título")
    end

    it "sem meta título/descrição usa o título e a descrição curta da página" do
      page.update!(meta_title: "", meta_description: "", description: "Descrição curta da página")

      get public_landing_page_path(page.slug)

      expect(seo_tags).to include(title: "Título interno", description: "Descrição curta da página")
    end

    it "um SEO editado à mão no módulo de SEO continua mandando" do
      get public_landing_page_path(page.slug)
      tenant.seo_settings.where("canonical_key LIKE 'landing_pages_show%'").update_all(manual_mode: true, meta_title: "Título manual", meta_description: "Descrição manual")
      Rails.cache.clear

      get public_landing_page_path(page.slug)

      expect(seo_tags).to include(title: "Título manual", description: "Descrição manual")
    end
  end

  describe "blocos de mídia" do
    it "vídeo usa o player de privacidade e imagem usa o alt e o link" do
      page = page_with([
        ["video", { "url" => "https://youtu.be/dQw4w9WgXcQ", "title" => "Tour" }],
        ["image", { "alt" => "Fachada", "caption" => "Vista frontal", "link" => "/contato" }]
      ])
      page.blocks.find_by(block_type: "image").image_desktop.attach(io: StringIO.new(File.binread(Rails.root.join("public/icon.png"))), filename: "f.png", content_type: "image/png")

      get public_landing_page_path(page.slug)

      expect(html.at_css("iframe[src='https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?rel=0']")["title"]).to eq("Tour")
      expect(html.at_css(".public-theme-block-image a[href='/contato'] img")["alt"]).to eq("Fachada")
      expect(html.at_css(".public-theme-block-image__caption").text).to eq("Vista frontal")
    end

    it "iframe incorporado sai isolado (sandbox); sem endereço válido, vídeo, iframe e imagem não aparecem" do
      page = page_with([["embed", { "url" => "https://example.com/mapa", "height" => "600" }], ["video", {}], ["image", {}], ["embed", {}]])

      get public_landing_page_path(page.slug)

      frames = html.css("iframe")
      expect(frames.size).to eq(1)
      expect(frames.first["src"]).to eq("https://example.com/mapa")
      expect(frames.first["sandbox"]).to include("allow-scripts")
      expect(html.at_css(".public-theme-block-embed.is-height-600")).to be_present
      expect(html.css(".public-theme-block-video, .public-theme-block-image")).to be_empty
    end
  end

  describe "colunas da página" do
    def build(columns, spans)
      page_with(spans.map { |span| ["text", { "heading" => "Bloco #{span}", "span" => span }] }, layout_columns: columns)
    end

    it "página de 3 colunas agrupa blocos de coluna consecutivos numa linha em grade" do
      page = build(3, %w[1 1 1 full])

      get public_landing_page_path(page.slug)

      row = html.at_css(".public-landing-page__row.has-cols-3")
      expect(row.css(".public-landing-page__cell.is-span-1").size).to eq(3)
      expect(html.css(".public-landing-page__row").size).to eq(1)
      expect(html.css("section.public-theme-block-text").size).to eq(4)
      expect(html.css(".public-landing-page__row section.public-theme-block-text").size).to eq(3) # o de linha inteira fica fora da grade
    end

    it "bloco de 2 colunas ocupa dois terços; com 1 coluna na página tudo é linha inteira" do
      get public_landing_page_path(build(3, %w[2 1]).slug)
      expect(html.at_css(".public-landing-page__cell.is-span-2")).to be_present

      tenant.landing_pages.destroy_all
      page = build(1, %w[1 1])
      get public_landing_page_path(page.slug)
      expect(html.css(".public-landing-page__row")).to be_empty
    end

    it "bloco da largura total das colunas (2 de 2) vira linha inteira" do
      page = build(2, %w[2 1])
      get public_landing_page_path(page.slug)
      expect(html.css(".public-landing-page__row .is-span-1").size).to eq(1)
      expect(html.css(".public-landing-page__row .is-span-2")).to be_empty
    end
  end

  describe "status e escopo" do
    it "rascunho e inativa voltam à home com aviso; só publicada abre; slug inexistente é 404" do
      draft = page_with([["text", { "heading" => "Oi" }]], slug: "rascunho-x", status: "draft")
      inactive = page_with([["text", { "heading" => "Oi" }]], slug: "inativa-x", status: "inactive")

      { draft => "em rascunho", inactive => "inativa" }.each do |page, text|
        get public_landing_page_path(page.slug)
        expect(response).to redirect_to(root_path), page.slug
        follow_redirect!
        expect(response.body).to include("ax-flash-toast", text), page.slug
      end

      get public_landing_page_path("nao-existe-x")
      expect(response).to have_http_status(:not_found)

      published = page_with([["text", { "heading" => "No ar" }]], slug: "no-ar-x")
      get public_landing_page_path(published.slug)
      expect(response).to have_http_status(:ok)
    end

    it "página sem blocos continua na tela original (rede de segurança)" do
      create(:habitation, categoria: "Apartamento", titulo_anuncio: "Apto legado")
      page = tenant.landing_pages.create!(title: "Legada", slug: "legada", filter_params: { "category" => "Apartamento" })

      get public_landing_page_path(page.slug)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Apto legado")
      expect(html.at_css(".public-theme-block-showcase--default")).to be_nil
    end
  end
  describe "composição institucional em todos os temas" do
    Tenant::PUBLIC_SITE_THEMES.each_key do |theme|
      it "agrupa blocos por coluna, separa seções e renderiza coleções no tema #{theme}" do
        tenant.update!(public_site_theme: theme)
        page = page_with([
          ["section", { "heading" => "Nossa empresa", "columns" => 2, "ratio" => "wide-first" }],
          ["text", { "heading" => "Apresentação", "column" => "1", "expandable" => true, "more_body" => "<p>História da empresa</p>", "offset_y" => -80, "layout_height" => "custom", "layout_min_height" => 300 }],
          ["button", { "label" => "Contato", "url" => "/contato", "column" => "1", "icon" => "whatsapp", "custom_colors" => true, "text_color" => "#ffffff", "background_color" => "#123456" }],
          ["video", { "url" => "https://vimeo.com/123456789", "column" => "2" }],
          ["section", { "heading" => "Valores", "columns" => 3 }],
          *LandingPages::BlockTypes::COLLECTIONS.keys.map { |kind| [kind, { "heading" => kind, "column" => "3", "layout" => "carousel", "items" => [{ "title" => "Dado desta conta", "label" => "2026", "text" => "Descrição", "image" => "https://example.com/photo.webp", "alt" => "Equipe", "url" => "/contato" }] }] }
        ])
        get public_landing_page_path(page.slug)
        expect(response).to have_http_status(:ok)
        sections = html.css(".public-theme-block-section")
        expect(sections.size).to eq(2)
        columns = sections.first.css(".public-theme-block-section__column")
        expect(columns.first.text).to include("Apresentação", "Contato", "História da empresa")
        expect(columns.first.at_css(".public-theme-block-layout.is-height-custom")["style"]).to include("--lp-offset-y:-80px", "--lp-layout-min-height:300px")
        expect(columns.first.at_css(".public-theme-block-button__link")["style"]).to include("background-color:#123456")
        expect(columns.first.at_css(".public-theme-block-button__link .bi-whatsapp")).to be_present
        expect(columns.last.at_css("iframe")["src"]).to eq("https://player.vimeo.com/video/123456789?dnt=1")
        expect(html.css("details.public-theme-block-text__more summary").text).to eq("Ver mais")
        expect(html.css(".public-theme-block-collection").size).to eq(7)
        expect(html.css(".public-theme-block-collection__image").map { |image| image["loading"] }.uniq).to eq(["lazy"])
        expect(html.css("h1").size).to eq(1)
      end
    end
  end

  it "mantém o player fora do carregamento inicial quando configurado para clicar" do
    page = page_with([["video", { "url" => "https://youtu.be/dQw4w9WgXcQ", "title" => "Tour da empresa", "click_to_play" => true }]])
    get public_landing_page_path(page.slug)
    expect(html.css(".public-theme-block-video iframe")).to be_empty
    expect(html.at_css("[data-controller='public-video']")["href"]).to eq("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?rel=0")
    expect(response.body).to include("Reproduzir Tour da empresa")
  end

  it "separa um bloco de largura total em uma linha própria dentro da seção" do
    page = page_with([
      ["section", { "columns" => 2 }],
      ["text", { "heading" => "Antes", "column" => "1" }],
      ["button", { "label" => "Largura total", "url" => "/contato", "layout_width" => "page" }],
      ["text", { "heading" => "Depois", "column" => "2" }]
    ])
    get public_landing_page_path(page.slug)
    expect(response).to have_http_status(:ok)
    wide = html.at_css(".public-theme-block-layout.is-width-page")
    expect(wide.text).to include("Largura total")
    expect(wide.ancestors(".public-theme-block-section__column")).to be_empty
    expect(html.css(".public-theme-block-section__grid").size).to eq(2)
    expect(response.body.index("Antes")).to be < response.body.index("Largura total")
    expect(response.body.index("Largura total")).to be < response.body.index("Depois")
  end

  it "não repete a imagem anexada do item anterior em um item sem imagem" do
    page = page_with([["team", { "items" => [{ "title" => "Com foto", "image_key" => "photo-1" }, { "title" => "Sem foto" }] }]])
    block = page.blocks.first
    block.item_images.attach(io: File.open(Rails.root.join("spec/fixtures/files/watermark.png")), filename: "watermark.png", content_type: "image/png", metadata: { landing_page_item_key: "photo-1" })

    get public_landing_page_path(page.slug)

    items = html.css(".public-theme-block-collection__item")
    expect(items.first.css("img").size).to eq(1)
    expect(items.last.css("img")).to be_empty
  end

end
