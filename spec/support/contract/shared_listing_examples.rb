RSpec.shared_examples "contrato da listagem pública" do
  it "expõe o gancho canônico do grid nas duas variantes (padrão e luxury)" do
    expect(listing_source).to include("public-theme-property-grid--default")
    expect(listing_source).to include("public-theme-property-grid--salute-luxury").or include('variant: "salute-luxury"')
    expect(listing_source).to include("public-habitations-index__grid")
  end

  it "ordena resultados antes de paginação, SEO e buscas relacionadas" do
    grid_position = listing_source.index("public-habitations-index__grid")
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
