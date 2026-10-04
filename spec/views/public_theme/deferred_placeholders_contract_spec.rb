require "rails_helper"

RSpec.describe "placeholders do conteúdo diferido público", type: :view do
  it "renderiza skeleton com cards, papel de status e rótulo" do
    render "public_theme/components/section_skeleton", variant: "default"

    doc = Nokogiri::HTML(rendered)
    status = doc.at_css(".public-theme-section-skeleton--default[role='status']")
    expect(status["aria-label"]).to eq("Carregando imóveis")
    expect(doc.css(".public-theme-section-skeleton__card").size).to eq(3)
    expect(doc.css(".public-theme-section-skeleton__media").size).to eq(3)
    expect(doc.at_css(".public-theme-section-skeleton__strip")["aria-hidden"]).to eq("true")
  end

  it "aceita variante, quantidade e rótulo no skeleton" do
    render "public_theme/components/section_skeleton",
           variant: "salute-luxury", cards: 5, label: "Carregando vídeos"

    doc = Nokogiri::HTML(rendered)
    expect(doc.at_css(".public-theme-section-skeleton--salute-luxury[role='status']")["aria-label"]).to eq("Carregando vídeos")
    expect(doc.css(".public-theme-section-skeleton__card").size).to eq(5)
  end

  it "fia o skeleton nos frames lazy da home, sem caixa vazia" do
    home = Rails.root.join("app/views/home/index.html.erb").read

    expect(home.scan("components/section_skeleton").size).to eq(3)
    expect(home).not_to include("public-theme-section__loading")
  end

  it "estiliza o skeleton no default com sheen e reduced-motion" do
    css = Rails.root.join("app/assets/stylesheets/components/_public_theme_home.scss").read

    expect(css).to include(
      "public-theme-section-skeleton__strip",
      "@keyframes public-theme-skeleton-sheen",
      "prefers-reduced-motion"
    )
  end

  it "cobre o skeleton na pele luxury" do
    luxury = Rails.root.join("app/assets/stylesheets/public_site_themes/salute_luxury.css").read

    expect(luxury).to include("public-theme-section-skeleton--salute-luxury")
  end

  it "reserva proporção do banner com fallback mobile" do
    banner = Rails.root.join("app/views/shared/_banner.html.erb").read
    banner_css = Rails.root.join("app/assets/stylesheets/components/_public_theme_banner.scss").read
    app_css = Rails.root.join("app/assets/stylesheets/application.scss").read

    expect(banner).to include("width: desktop_dimensions.first", "height: desktop_dimensions.last", "width: mobile_dimensions.first", "public-theme-banner__image--responsive")
    expect(banner_css).to include("height: auto")
    expect(app_css).to include('@use "components/public_theme_banner"')
  end

  it "reserva proporção das fotos da galeria de detalhe" do
    gallery = Rails.root.join("app/views/public_theme/components/_property_gallery.html.erb").read

    expect(gallery).to include("width: 1200", "height: 900", "width: 560", "height: 420")
  end

  it "sinaliza busy na grade durante navegação do frame" do
    js = Rails.root.join("app/javascript/controllers/public_listing_nav_controller.js").read
    css = Rails.root.join("app/assets/stylesheets/public_habitations_index_refresh.css").read

    expect(js).to include("setFrameBusy", "aria-busy", "turbo:frame-load", "turbo:fetch-request-error")
    expect(css).to include("#public-listing-grid.is-loading")
  end

  it "mostra spinner até o mapa carregar, em todos os temas" do
    map = Rails.root.join("app/views/public_theme/components/_property_map.html.erb").read
    js = Rails.root.join("app/javascript/controllers/public_property_map_controller.js").read
    css = Rails.root.join("app/assets/stylesheets/public_habitations_show_refresh.css").read
    luxury = Rails.root.join("app/assets/stylesheets/public_site_themes/salute_luxury.css").read

    expect(map).to include("public-theme-property-map__loader", 'data-public-property-map-target="loader"')
    expect(js).to include('"loader"', "hideLoader")
    expect(css).to include("public-theme-map-loader-spin", "prefers-reduced-motion")
    expect(luxury).to include("public-theme-property-map--salute-luxury .public-theme-property-map__loader")
  end
end
