require "rails_helper"

RSpec.describe "Redirect de busca por código", type: :request do
  let(:tenant) { Tenant.default }

  before { host! "localhost" }

  it "vai direto à página do imóvel com código exato" do
    create(:habitation, tenant: tenant, codigo: "972904", status: "Aluguel",
      valor_venda_cents: 0, valor_locacao_cents: 890_200,
      titulo_anuncio: "Apartamento redirect código")

    get "/imoveis", params: { transaction_type: "venda", search: "972904" }

    expect(response).to have_http_status(:found)
    expect(response.location).to match(/972904/)
  end

  it "aceita REF e # no redirect por código" do
    create(:habitation, tenant: tenant, codigo: "972905", status: "Venda",
      titulo_anuncio: "Casa redirect prefixo")

    get "/imoveis", params: { search: "REF 972905" }

    expect(response).to have_http_status(:found)
    expect(response.location).to match(/972905/)
  end

  it "mantém a listagem para texto sem código exato" do
    get "/imoveis", params: { transaction_type: "venda", search: "mobiliado" }

    expect(response).to have_http_status(:ok)
  end
end
