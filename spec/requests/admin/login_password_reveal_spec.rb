require "rails_helper"

RSpec.describe "Admin login password reveal", type: :request do
  before { host! "localhost" }

  it "renderiza o botão próprio de mostrar senha no login" do
    get "/admin/sign_in"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("login-control--password")
    expect(response.body).to include("data-login-reveal")
    expect(response.body).to include('aria-label="Mostrar senha"')
  end

  it "mantem a marca do tenant no login web comum" do
    LayoutSetting.instance(tenant: Tenant.public_for).update!(site_name: "Conexão Imobiliária")

    get "/admin/sign_in"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<h1>Conexão Imobiliária</h1>")
    expect(response.body).to include("#{Time.current.year} Conexão Imobiliária")
  end

  it "usa Unitymob no login do app nativo para nao publicar com nome de cliente" do
    LayoutSetting.instance(tenant: Tenant.public_for).update!(site_name: "Conexão Imobiliária")

    get "/admin/sign_in", headers: { "HTTP_USER_AGENT" => "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) UnitymobFieldApp" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<h1>Unitymob</h1>")
    expect(response.body).to include("#{Time.current.year} Unitymob")
    expect(response.body).not_to include("<h1>Conexão Imobiliária</h1>")
  end

  it "renderiza recuperacao de senha sem exigir tenant para tracking" do
    expect(TrackingIntegrationSetting).not_to receive(:current)

    get "/admin/password/new"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Esqueceu sua senha?")
  end
end
