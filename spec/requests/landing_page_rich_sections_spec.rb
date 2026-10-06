require "rails_helper"

RSpec.describe "Composições ricas do construtor", type: :request do
  let(:tenant) { Tenant.default }
  before { host! "localhost" }

  Tenant::PUBLIC_SITE_THEMES.each_key do |theme|
    it "renderiza capa, estilos, FAQ, etapas e âncoras no tema #{theme}" do
      tenant.update_columns(public_site_theme: theme)
      page = tenant.landing_pages.create!(title: "Página rica", slug: "pagina-rica", status: "published")
      [
        ["cover", { design: "split", title: "Uma nova história", button_label: "Contato", button_url: "/contato", secondary_label: "Benefícios", secondary_url: "#beneficios" }],
        ["navigation", { items: [{ title: "Benefícios", url: "#beneficios" }, { title: "Inválido", url: "javascript:alert(1)" }] }],
        ["section", { columns: 1, anchor: "beneficios", surface: "brand", density: "balanced", typography: "editorial", motion: "subtle" }],
        ["steps", { card_style: "outline", mobile_presentation: "carousel", items: [{ title: "Converse", text: "Conte seus objetivos" }] }],
        ["callout", { heading: "Aluguel garantido", text: "Mais tranquilidade", badge: "Contratos Salute", icon: "shield-check", button_label: "Contato", button_url: "/contato", secondary_label: "Imóveis", secondary_url: "/imoveis", surface: "dark" }],
        ["faq", { filter_categories: true, searchable: true, open_answers: true, items: [{ title: "Como começar?", text: "Fale com a equipe <script>alert(1)</script>", group: "Compra", categories: "Compra, Documentação" }, { title: "Destaque", text: "Texto de apoio", featured: true, group: "Locação", categories: "Locação", badge: "Selo" }] }]
      ].each_with_index { |(type, data), position| page.blocks.create!(block_type: type, data: data, position: position) }
      get public_landing_page_path(page.slug)
      expect(response).to have_http_status(:ok)
      html = Nokogiri::HTML(response.body)
      expect(html.css("h1").size).to eq(1)
      expect(html.at_css(".public-theme-block-cover.is-design-split")).to be_present
      expect(html.at_css(".public-theme-block-cover__button--secondary")["href"]).to eq("#beneficios")
      expect(html.at_css("#beneficios.lp-surface-brand.lp-density-balanced")).to be_present
      expect(html.at_css(".is-kind-steps.is-card-outline.is-mobile-carousel")).to be_present
      expect(html.at_css(".public-theme-block-collection__step").text).to eq("01")
      expect(html.at_css(".public-theme-block-faq__item summary").text).to include("Como começar?")
      expect(html.at_css(".public-theme-block-faq__answer script")).to be_nil
      expect(html.at_css(".public-theme-block-faq__item")["open"]).not_to be_nil
      expect(html.css(".public-theme-block-faq__filters button").map(&:text)).to eq(["Todas", "Compra", "Documentação", "Locação"])
      expect(html.at_css("input[data-public-faq-target='search']")).to be_present
      expect(html.css(".public-theme-content-callout").size).to eq(2)
      expect(html.at_css(".public-theme-content-callout__button--secondary")["href"]).to eq("/imoveis")
      expect(html.css(".public-theme-block-navigation a").size).to eq(1)
    end
  end

  it "mantém defaults anteriores e normaliza opções e âncoras" do
    legacy = LandingPages::BlockTypes.fetch("cards").normalize({})
    expect(legacy).to include("card_style" => "legacy", "surface" => "inherit", "motion" => "none", "mobile_presentation" => "inherit")
    data = LandingPages::BlockTypes.fetch("section").normalize(surface: "red;script", anchor: "Nossa História", motion: "evil", mobile_order: "reverse")
    expect(data).to include("surface" => "inherit", "anchor" => "nossa-historia", "motion" => "none", "mobile_order" => "reverse")
  end

  it "não cria cards vazios a partir de campos auxiliares e limita estrelas e campos da FAQ" do
    expect(LandingPages::BlockTypes.fetch("testimonials").normalize(items: [{}])["items"]).to eq([])
    row = LandingPages::BlockTypes.fetch("testimonials").normalize(items: [{title: "Cliente", rating: 99, initials: "ABCDEF"}])["items"].first
    expect(row).to include("rating" => 5, "initials" => "ABCD")
    faq = LandingPages::BlockTypes.fetch("faq").normalize(items: [{title: "Pergunta", featured: "1", icon: 'x" onclick=x', secret: "x"}])["items"].first
    expect(faq).to include("featured" => true, "icon" => "")
    expect(faq).not_to have_key("secret")
  end

  it "todos os modelos e seções prontas podem ser salvos como rascunho" do
    LandingPages::Templates::ALL.each do |template|
      page = tenant.landing_pages.build(title: "Modelo #{template.key}", status: "draft")
      template.blocks.each_with_index { |attrs, position| page.blocks.build(attrs.merge(position: position)) }
      expect(page.save).to eq(true), "#{template.key}: #{page.errors.full_messages.join(', ')}"
      expect(page.reload.blocks.map(&:block_type)).to eq(template.blocks.map { |attrs| attrs[:block_type] })
    end
  end
end
