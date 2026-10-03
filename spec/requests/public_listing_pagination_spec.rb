require "rails_helper"

RSpec.describe "Public listing pagination", type: :request do
  before { host! "localhost" }

  def create_sale_listing(codigo)
    create(:habitation, codigo: codigo, status: "Venda", valor_venda_cents: 500_000_00, valor_locacao_cents: 0)
  end

  def create_rent_listing(codigo)
    create(:habitation, codigo: codigo, status: "Aluguel", valor_venda_cents: 0, valor_locacao_cents: 3_000_00)
  end

  def result_codes
    Nokogiri::HTML(response.body).css("[data-property-code]").map { |node| node["data-property-code"] }
  end

  def pagination_hrefs
    Nokogiri::HTML(response.body).css(".public-theme-pagination a[href]").map { |node| node["href"] }
  end

  before do
    13.times { |i| create_sale_listing("VENDA-PAG-#{i}") }
    create_rent_listing("ALUGUEL-PAG-1")
    create_rent_listing("ALUGUEL-PAG-2")
  end

  it "mantém o path amigável nos links de paginação" do
    get "/imoveis/venda"

    expect(response).to have_http_status(:ok)
    hrefs = pagination_hrefs
    expect(hrefs).not_to be_empty
    expect(hrefs).to all(start_with("/imoveis/venda"))
    expect(hrefs).to include("/imoveis/venda?page=2")
  end

  it "página 2 da busca amigável mantém o filtro" do
    get "/imoveis/venda?page=2"

    expect(response).to have_http_status(:ok)
    codes = result_codes
    expect(codes.size).to eq(1)
    expect(codes.first).to start_with("VENDA-PAG-")
    expect(response.body).not_to include("ALUGUEL-PAG-")
  end

  it "entrega só a grade ao Turbo, preservando os imóveis filtrados" do
    get "/imoveis/venda?page=2", headers: { "Turbo-Frame" => "public-listing-grid" }

    expect(response).to have_http_status(:ok)
    expect(result_codes.size).to eq(1)
    expect(result_codes.first).to start_with("VENDA-PAG-")
    expect(response.body).to include('id="public-listing-grid"')
    expect(response.body).not_to include("<!DOCTYPE", "advanced-filters-form", "ALUGUEL-PAG-")
  end

  it "não oferece páginas que ultrapassam a proteção do servidor" do
    allow_any_instance_of(HabitationsController).to receive(:cached_listing_total_entries).and_return(1200)
    get "/imoveis/venda"

    expect(pagination_hrefs).to include("/imoveis/venda?page=50")
    expect(pagination_hrefs.none? { |href| href.match?(/page=(?:5[1-9]|[6-9]\d|\d{3,})\b/) }).to be(true)
  end

  it "não emite page=1 nos links de retorno" do
    get "/imoveis/venda?page=2"

    expect(pagination_hrefs).to include("/imoveis/venda")
    expect(pagination_hrefs.none? { |href| href.include?("page=1") }).to be(true)
  end

  it "preserva query params na paginação de busca por query string" do
    get "/imoveis", params: { transaction_type: "venda" }

    hrefs = pagination_hrefs
    expect(hrefs).not_to be_empty
    expect(hrefs).to all(start_with("/imoveis?"))
    expect(hrefs).to include("/imoveis?page=2&transaction_type=venda")
  end

  it "ordenação mantém o path amigável e reseta a página" do
    get "/imoveis/venda"

    values = Nokogiri::HTML(response.body).css("#public-habitations-sort option").map { |node| node["value"] }
    expect(values).not_to be_empty
    expect(values).to all(start_with("/imoveis/venda"))
    expect(values.none? { |value| value.include?("page=") }).to be(true)
  end

  it "nova pesquisa não carrega page e limpar volta ao início" do
    get "/imoveis/venda?page=2"

    doc = Nokogiri::HTML(response.body)
    expect(doc.css("form#advanced-filters-form input[name='page']")).to be_empty
    expect(doc.css("form.public-habitations-index__filter-form input[name='page']")).to be_empty
    clear_link = doc.at_css("a.public-habitations-index__clear-link")
    expect(clear_link["href"]).to eq("/imoveis")
  end
end
