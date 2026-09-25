RSpec.shared_examples "contrato da listagem pública" do
  def grid_partial_source(theme_key)
    partial = Tenant::PUBLIC_SITE_THEMES.fetch(theme_key).fetch(:components).fetch(:property_grid)
    dirname, _, basename = partial.rpartition("/")
    Rails.root.join("app/views", dirname, "_#{basename}.html.erb").read
  end

  it "expõe o gancho canônico do grid nas duas variantes (padrão e luxury)" do
    expect(listing_source).to include("theme_component(:property_grid")
    expect(grid_partial_source("default")).to include("public-theme-property-grid--default")
    expect(grid_partial_source("default")).to include("public-habitations-index__grid")
    expect(grid_partial_source("salute_luxury")).to include("public-theme-property-grid")
  end

  it "ordena resultados antes de paginação, SEO e buscas relacionadas" do
    grid_position = listing_source.index("theme_component(:property_grid")
    pagination_position = listing_source.index("public-habitations-index__pagination")
    seo_position = listing_source.index("public-habitations-index__seo-intro")
    related_position = listing_source.index("public-habitations-index__strategic-links")

    expect(grid_position).to be < pagination_position
    expect(pagination_position).to be < seo_position
    expect(pagination_position).to be < related_position
  end

  it "expõe estado vazio com ação de limpar filtros" do
    expect(listing_source).to include("public-habitations-index__empty")
    expect(listing_source).to include("Nenhum imóvel encontrado")
    expect(listing_source).to include("Limpar filtros")
  end
end
