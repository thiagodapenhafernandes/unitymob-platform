require "rails_helper"

# Matriz de validação da gramática nova (/imoveis/venda/...): cada linha
# prova que a URL filtra exatamente os imóveis esperados, de ponta a ponta
# (rota → parse → scopes). Paralelo legado incluído no fim.
RSpec.describe "Public listing URL matrix", type: :request do
  before { host! "localhost" }

  def create_listing(code, **attrs)
    defaults = {
      codigo: code,
      titulo_anuncio: "Anúncio #{code}",
      status: "Venda",
      valor_venda_cents: 0,
      valor_locacao_cents: 0
    }
    create(:habitation, **defaults.merge(attrs))
  end

  before do
    create_listing("MAT-A",
      categoria: "Apartamento", dormitorios_qtd: 2, suites_qtd: 1, vagas_qtd: 1,
      banheiros_qtd: 2, area_total_m2: 70, valor_venda_cents: 600_000_00,
      mobiliado_flag: true, titulo_anuncio: "Vista Atlântica")
      .tap { |h| h.address.update!(cidade: "Balneário Camboriú", bairro: "Centro") }
    create_listing("MAT-B",
      categoria: "Casa", dormitorios_qtd: 3, suites_qtd: 2, vagas_qtd: 2,
      banheiros_qtd: 3, area_total_m2: 150, valor_venda_cents: 1_200_000_00,
      caracteristicas: { "sacada" => "Sacada", "churrasqueira" => "Churrasqueira" },
      titulo_anuncio: "Casa Meia Praia")
      .tap { |h| h.address.update!(cidade: "Itapema", bairro: "Meia Praia") }
    create_listing("MAT-C",
      categoria: "Apartamento", dormitorios_qtd: 2, suites_qtd: 1, vagas_qtd: 1,
      banheiros_qtd: 2, area_total_m2: 40, valor_venda_cents: 400_000_00,
      titulo_anuncio: "Apartamento Centro Econômico")
    create_listing("MAT-D",
      categoria: "Apartamento", dormitorios_qtd: 4, suites_qtd: 1, vagas_qtd: 1,
      banheiros_qtd: 4, area_total_m2: 200, valor_venda_cents: 2_000_000_00,
      titulo_anuncio: "Cobertura Familiar")
    create_listing("MAT-E",
      categoria: "Apartamento", status: "Aluguel", dormitorios_qtd: 2,
      suites_qtd: 1, vagas_qtd: 1, banheiros_qtd: 2, area_total_m2: 65,
      valor_locacao_cents: 3_000_00, titulo_anuncio: "Aluguel Centro")
  end

  def codes_for(path)
    get path, params: { format: :json }
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body).map { |item| item.fetch("codigo") }
  end

  {
    "/imoveis/venda" => %w[MAT-A MAT-B MAT-C MAT-D],
    "/imoveis/aluguel" => %w[MAT-E],
    "/imoveis/venda/apartamento" => %w[MAT-A MAT-C MAT-D],
    "/imoveis/venda/apartamento+casa" => %w[MAT-A MAT-B MAT-C MAT-D],
    "/imoveis/venda/itapema" => %w[MAT-B],
    "/imoveis/venda/meia-praia-itapema" => %w[MAT-B],
    "/imoveis/venda/2-quartos" => %w[MAT-A MAT-C],
    "/imoveis/venda/2-quartos+3-quartos" => %w[MAT-A MAT-B MAT-C],
    "/imoveis/venda/4-mais-quartos" => %w[MAT-D],
    "/imoveis/venda/2-suites" => %w[MAT-B],
    "/imoveis/venda/2-vagas" => %w[MAT-B],
    "/imoveis/venda/3-banheiros" => %w[MAT-B],
    "/imoveis/venda/2-banheiros" => %w[MAT-A MAT-C],
    "/imoveis/venda/4-mais-banheiros" => %w[MAT-D],
    "/imoveis/venda/50-100m2" => %w[MAT-A],
    "/imoveis/venda/ate-500-mil" => %w[MAT-C],
    "/imoveis/venda/500-mil-1-milhao" => %w[MAT-A],
    "/imoveis/venda/1-milhao-2-milhoes" => %w[MAT-B MAT-D],
    "/imoveis/aluguel/2-mil-5-mil" => %w[MAT-E],
    "/imoveis/venda/mobiliado" => %w[MAT-A],
    "/imoveis/venda/sacada+churrasqueira" => %w[MAT-B],
    "/imoveis/venda/apartamento/balneario-camboriu/2-quartos/500-mil-1-milhao/mobiliado" => %w[MAT-A],
    "/imoveis/venda/busca-vista-atlantica" => %w[MAT-A]
  }.each do |path, expected|
    it "filtra #{path} => #{expected.join(",")}" do
      expect(codes_for(path)).to match_array(expected)
    end
  end

  it "legado em query string segue 200 em paralelo" do
    get "/imoveis",
      params: { transaction_type: "venda", category: ["Apartamento"], format: :json }

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).map { |item| item.fetch("codigo") })
      .to match_array(%w[MAT-A MAT-C MAT-D])
  end
end
