require "rails_helper"

RSpec.describe "Public frames (lazy)", type: :request do
  before { host! "localhost" }

  let(:tenant) { Tenant.default }

  it "serve slides 2..N do hero sem layout" do
    get "/frames/home_hero_slides"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="home-hero-slides"')
    expect(response.body).not_to include("<html")
  end

  it "serve carrossel da seção com os imóveis selecionados" do
    first = create(:habitation, tenant:, categoria: "Apartamento", codigo: "FRAME-A")
    second = create(:habitation, tenant:, categoria: "Apartamento", codigo: "FRAME-B")
    section = HomeSection.create!(
      tenant:, section_type: :featured_properties, title: "Destaques",
      active: true, property_filters: { "selected_property_ids" => [first.id, second.id] }
    )

    get "/frames/home_sections/#{section.id}", params: { part: "properties" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("home-section-#{section.id}")
    expect(response.body).to include("FRAME-A")
    expect(response.body).to include("FRAME-B")
  end

  it "primeira seção pesada inline e demais em lazy frame" do
    first = create(:habitation, tenant:, categoria: "Apartamento", codigo: "FRAME-H1")
    second = create(:habitation, tenant:, categoria: "Apartamento", codigo: "FRAME-H2")
    HomeSection.create!(tenant:, section_type: :featured_properties, title: "Um",
      active: true, order_position: 1,
      property_filters: { "selected_property_ids" => [first.id] })
    HomeSection.create!(tenant:, section_type: :featured_properties, title: "Dois",
      active: true, order_position: 2,
      property_filters: { "selected_property_ids" => [second.id] })

    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("FRAME-H1")
    expect(response.body).not_to include("FRAME-H2")
    expect(response.body).to include("loading=\"lazy\"")
  end

  it "responde 404 para seção de outro tenant" do
    other = Tenant.create!(name: "Outra", slug: "outra-frame")
    section = HomeSection.create!(
      tenant: other, section_type: :featured_properties, title: "X", active: true
    )

    get "/frames/home_sections/#{section.id}", params: { part: "properties" }

    expect(response).to have_http_status(:not_found)
  end

  it "listagem expõe o frame da grade e o sort navegando nele" do
    create(:habitation, tenant:, categoria: "Apartamento", codigo: "FRAME-LIST")

    get "/imoveis/venda"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="public-listing-grid"')
    expect(response.body).to include('data-turbo-action="advance"')
    expect(response.body).to include("change->public-listing-nav#sort")
  end
end
