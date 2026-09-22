require "rails_helper"

RSpec.describe "LandingPages", type: :request do
  before do
    host! "localhost"
  end

  it "orders public listing by price and keeps canonical pagination links for the landing slug" do
    landing_page = LandingPage.create!(
      title: "Apartamentos",
      slug: "apartamentos",
      active: true,
      filter_params: { "category" => "Apartamento" }
    )
    lower_price = create(:habitation, categoria: "Apartamento", titulo_anuncio: "Apartamento menor valor", valor_venda_cents: 500_000_00)
    higher_price = create(:habitation, categoria: "Apartamento", titulo_anuncio: "Apartamento maior valor", valor_venda_cents: 600_000_00)
    11.times do |index|
      create(:habitation, categoria: "Apartamento", titulo_anuncio: "Apartamento pagina #{index}", valor_venda_cents: 700_000_00 + index)
    end

    get public_landing_page_path(landing_page.slug, sort: "price_asc")

    expect(response).to have_http_status(:ok)
    expect(response.body.index(lower_price.titulo_anuncio)).to be < response.body.index(higher_price.titulo_anuncio)
    expect(response.body).to include('/apartamentos?page=2&amp;sort=price_asc')
    expect(response.body).not_to include('/landing_pages/')
  end

  it "limits public listing to selected property codes" do
    included = create(:habitation, codigo: "LP-CODE-1", titulo_anuncio: "Imóvel escolhido para landing", exibir_no_site_flag: true)
    excluded = create(:habitation, codigo: "LP-CODE-2", titulo_anuncio: "Imóvel fora da landing", exibir_no_site_flag: true)
    landing_page = LandingPage.create!(
      title: "Seleção por código",
      slug: "selecao-por-codigo",
      active: true,
      filter_params: { "property_codes" => [included.codigo] }
    )

    get public_landing_page_path(landing_page.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(included.titulo_anuncio)
    expect(response.body).not_to include(excluded.titulo_anuncio)
  end

  # Regressão: os multiselects do admin gravam [""]; isso contava como filtro e a página pública/prévia ficava sempre vazia.
  it "ignora entradas vazias ([\"\"]) dos multiselects e lista os imóveis normalmente" do
    listed = create(:habitation, titulo_anuncio: "Aparece mesmo com filtros vazios", exibir_no_site_flag: true)
    landing_page = LandingPage.create!(title: "Sem filtros reais", slug: "sem-filtros-reais", active: true)
    landing_page.update_columns(filter_params: { "property_codes" => [""], "city" => [""], "category" => [""], "development" => [""], "neighborhood" => [""] })

    get public_landing_page_path(landing_page.slug)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(listed.titulo_anuncio)
  end
end
