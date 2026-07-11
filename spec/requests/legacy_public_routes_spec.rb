require "rails_helper"

RSpec.describe "Legacy public routes", type: :request do
  let!(:tenant) { Tenant.default }

  before { host! "localhost" }

  it "redireciona uma URL antiga pelo código para a URL canônica do imóvel" do
    habitation = create(:habitation, tenant: tenant, codigo: "8234", status: "Venda", exibir_no_site_flag: true)

    get "/imovel/apartamento/venda/balneario-camboriu/centro/8234"

    expect(response).to redirect_to(habitation_path(habitation))
    expect(response).to have_http_status(:moved_permanently)
  end

  it "redireciona uma busca antiga de venda para a listagem atual" do
    get "/venda/apartamento/balneario-camboriu/3-dormitorios"

    expect(response).to redirect_to(venda_path)
    expect(response).to have_http_status(:moved_permanently)
  end

  it "redireciona legado reconhecido sem correspondência para uma página útil" do
    get "/imovel/apartamento/venda/balneario-camboriu/centro/99999999"

    expect(response).to redirect_to(root_path)
    expect(response).to have_http_status(:moved_permanently)
  end

  it "responde 404 sem redirect para caminho suspeito com domínio anexado" do
    get "/venda/apartamento/balneario-camboriu/maps.googleapis.com"

    expect(response).to have_http_status(:not_found)
    expect(response).not_to be_redirect
  end

  it "mantém scanners fora do fallback de navegação" do
    get "/wp-login.php"

    expect(response).to have_http_status(:not_found)
  end
end
