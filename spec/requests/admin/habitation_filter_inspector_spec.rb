require "rails_helper"

RSpec.describe "Admin habitation filter inspector", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza o inspector em um turbo frame separado" do
    create(:habitation, bairro: "Centro")

    get filter_inspector_admin_habitations_path, headers: { "Turbo-Frame" => "admin_habitations_filter_inspector" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('turbo-frame id="admin_habitations_filter_inspector"')
    expect(response.body).to include("Filtros do catálogo")
    expect(response.body).to include('autocomplete="off"')
    expect(response.body).to include('data-turbo-frame="_top"')
    expect(response.body).to include('name="codigo"')
    expect(response.body).to include('name="q"')
    expect(response.body).to include('name="logradouro"')
    expect(response.body.scan('autocomplete="off"').size).to be >= 8
    expect(response.body).to include('name="bairro[]"')
    expect(response.body).to include('multiple="multiple"')
    expect(response.body).to include('filter-multi-wrap')
    expect(response.body).to include('data-controller="tom-select"')
    expect(response.body).to include("Centro")
  end

  it "organiza os filtros principais conforme o catálogo compacto" do
    get filter_inspector_admin_habitations_path(q: "praia", min_price: "800000", max_price: "1200000"),
        headers: { "Turbo-Frame" => "admin_habitations_filter_inspector" }

    expect(response).to have_http_status(:ok)

    document = Nokogiri::HTML(response.body)
    quick_section = document.css(".ax-filter-section").find { |section| section.text.include?("Filtros rápidos") }

    expect(response.body.index("Filtros rápidos")).to be < response.body.index("Dados")
    expect(response.body).to include("Palavra-chave")
    expect(response.body).to include("Código / Referência")
    expect(response.body).to include("Empreendimento")
    expect(response.body).to include("Corretor")
    expect(response.body).to include("Recorte")
    expect(response.body).to include("Tipo e status")
    expect(document.at_css(".habitations-catalog-price-stack input[name='min_price']")).to be_present
    expect(document.at_css(".habitations-catalog-price-stack input[name='max_price']")).to be_present
    expect(quick_section.to_html).to include('name="q"')
  end

  it "renderiza características internas e lazer como bloco próprio do catálogo" do
    get filter_inspector_admin_habitations_path(amenities: ["Adega", "Garden"]),
        headers: { "Turbo-Frame" => "admin_habitations_filter_inspector" }

    expect(response).to have_http_status(:ok)

    document = Nokogiri::HTML(response.body)
    amenity_section = document.css(".ax-filter-section").find { |section| section.text.include?("Características internas e lazer") }

    expect(amenity_section).to be_present
    expect(amenity_section.to_html).to include('name="amenities[]"')
    expect(amenity_section.text).to include("Adega")
    expect(amenity_section.text).to include("Ar-condicionado")
    expect(amenity_section.text).to include("Garden")
    expect(amenity_section.text).to include("Quadra mar")
    expect(response.body.index("Características internas e lazer")).to be < response.body.index("Imagens e portais")
  end

  it "mantém o inspector pesado fora da primeira resposta da listagem" do
    get admin_habitations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="admin_habitations_filter_inspector"')
    expect(response.body).to include("habitations-inspector-skeleton")
    expect(response.body).not_to include('<form class="habitations-inspector__form"')
  end
end
