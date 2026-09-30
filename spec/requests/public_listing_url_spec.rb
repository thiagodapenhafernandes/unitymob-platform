require "rails_helper"

RSpec.describe "Public listing friendly URLs (novo core)", type: :request do
  before { host! "localhost" }

  def codes_from_json
    JSON.parse(response.body).map { |item| item.fetch("codigo") }
  end

  before do
    create(:habitation,
      codigo: "LIST-URL-2Q",
      categoria: "Apartamento",
      status: "Venda",
      dormitorios_qtd: 2,
      valor_venda_cents: 600_000_00,
      valor_locacao_cents: 0,
      mobiliado_flag: true)
      .tap { |habitation| habitation.address.update!(cidade: "Balneário Camboriú", bairro: "Centro") }
    create(:habitation,
      codigo: "LIST-URL-3Q",
      categoria: "Apartamento",
      status: "Venda",
      dormitorios_qtd: 3,
      valor_venda_cents: 900_000_00,
      valor_locacao_cents: 0)
      .tap { |habitation| habitation.address.update!(cidade: "Balneário Camboriú", bairro: "Centro") }
    create(:habitation,
      codigo: "LIST-URL-ALUGUEL",
      categoria: "Apartamento",
      status: "Aluguel",
      dormitorios_qtd: 2,
      valor_venda_cents: 0,
      valor_locacao_cents: 3_000_00)
      .tap { |habitation| habitation.address.update!(cidade: "Balneário Camboriú", bairro: "Centro") }
  end

  it "filtra pela gramática nova com OU de quartos" do
    get "/imoveis/venda/apartamento/centro-balneario-camboriu/2-quartos+3-quartos",
      params: { format: :json }

    expect(response).to have_http_status(:ok)
    expect(codes_from_json).to include("LIST-URL-2Q", "LIST-URL-3Q")
    expect(codes_from_json).not_to include("LIST-URL-ALUGUEL")
  end

  it "filtra por faixa de preço e característica" do
    get "/imoveis/venda/500-mil-700-mil/mobiliado", params: { format: :json }

    expect(response).to have_http_status(:ok)
    expect(codes_from_json).to include("LIST-URL-2Q")
    expect(codes_from_json).not_to include("LIST-URL-3Q", "LIST-URL-ALUGUEL")
  end

  it "responde 404 para slug estrutural desconhecido" do
    get "/imoveis/venda/busca-"

    expect(response).to have_http_status(:not_found)
  end

  it "redireciona atalhos de transação para o canônico novo" do
    get "/venda"
    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to("/imoveis/venda")

    get "/aluguel/apartamento"
    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to("/imoveis/aluguel/apartamento")
  end

  it "mantém oportunidade no alvo legado (venda + aluguel)" do
    get "/imoveis-com-oportunidade"

    expect(response).to have_http_status(:moved_permanently)
    expect(response.location).to include("/imoveis?characteristics[]=opportunity")
  end

  it "limpa segmentos todos com 301 preservando page e sort" do
    get "/imoveis/venda/todos/todos/sacada", params: { page: 2, sort: "price_desc" }

    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to("/imoveis/venda/sacada?page=2&sort=price_desc")
  end

  it "submit do form (v=2) redireciona para a gramática nova" do
    get "/imoveis",
      params: { v: "2", transaction_type: "venda", category: ["Apartamento"], bedrooms: "2" }

    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to("/imoveis/venda/apartamento/2-quartos")
  end

  it "URL antiga sem marcador continua 200 em paralelo" do
    get "/imoveis", params: { transaction_type: "venda", category: ["Apartamento"] }

    expect(response).to have_http_status(:ok)
    expect(response).not_to be_redirect

    get "/imoveis", params: { transaction_type: "venda", category: ["Apartamento"], format: :json }

    expect(response).to have_http_status(:ok)
    expect(codes_from_json).to include("LIST-URL-2Q", "LIST-URL-3Q")
  end

  it "submit vazio (v=2) volta para /imoveis limpo" do
    get "/imoveis", params: { v: "2", category: [""] }

    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to("/imoveis/")
  end

  it "submit com price_range canônico não vaza query" do
    get "/imoveis",
      params: {
        v: "2", transaction_type: "venda", category: %w[Apartamento Casa],
        city: ["Balneário Camboriú", "Balneário Piçarras"], price_range: "3200000-5800000"
      }

    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to(
      "/imoveis/venda/apartamento+casa/balneario-camboriu+balneario-picarras/3200000-5800000"
    )
  end

  it "link de cidade (v=2) canônico sem query" do
    get "/imoveis", params: { v: "2", transaction_type: "aluguel", city: ["Itapema"] }

    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to("/imoveis/aluguel/itapema")
  end

  it "link v=2 em página legada preserva transação e categoria" do
    get "/imoveis",
      params: { v: "2", friendly_transaction: "venda", friendly_categories: "apartamento" }

    expect(response).to have_http_status(:moved_permanently)
    expect(response).to redirect_to("/imoveis/venda/apartamento")
  end

  it "não redireciona submit v=2 em formato JSON" do
    get "/imoveis",
      params: { v: "2", transaction_type: "venda", category: ["Apartamento"], format: :json }

    expect(response).to have_http_status(:ok)
    expect(codes_from_json).to include("LIST-URL-2Q", "LIST-URL-3Q")
  end
end
