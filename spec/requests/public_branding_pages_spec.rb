require "rails_helper"

RSpec.describe "Public branding pages", type: :request do
  before do
    host! "localhost"
    tenant = Tenant.default
    LayoutSetting.instance(tenant: tenant).update!(site_name: "Marca Pública")
    ContactSetting.instance(tenant: tenant).update!(email_primary: "publico@example.com", phone: "(47) 3333-4444")
  end

  it "renderiza as páginas institucionais com a identidade configurada" do
    [sobre_path, contato_path, parcerias_path, trabalhe_conosco_path, corporativos_path, privacy_policy_path, terms_of_use_path].each do |path|
      get path

      expect(response).to have_http_status(:ok), "esperava HTTP 200 em #{path}, recebeu #{response.status}"
    end

    get parcerias_path
    expect(response.body).to include("Marca Pública")
    expect(response.body).not_to include("Salute Parcerias")
  end

  it "mantém o endereço antigo de parcerias acessível" do
    get "/salute-parcerias"

    expect(response).to have_http_status(:ok)
  end

  it "publica somente os links úteis persistidos para o tenant" do
    tenant = Tenant.default
    expect(PublicSiteProfile.new({ useful_links: "Portal próprio|https://portal.example.com|Serviço do tenant|building" }, tenant: tenant).save).to be(true)

    get links_uteis_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Portal próprio")
    expect(response.body).to include("https://portal.example.com")
    expect(response.body).not_to include("balneariocamboriu.sc.gov.br")
  end
end
