require "rails_helper"

RSpec.describe "Referência da API", type: :request do
  before { host! "localhost" }

  it "exibe a documentação sem login e aponta para o contrato OpenAPI" do
    get "/docs/api"

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    reference = page.at_css("elements-api")
    expect(reference["apidescriptionurl"]).to eq("/docs/openapi.yaml")
    expect(reference["hidetryitpanel"]).to eq("true")
  end

  it "entrega o contrato de captação com o servidor do ambiente e autenticação Bearer" do
    get "/docs/openapi.yaml"

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/yaml")
    spec = YAML.safe_load(response.body)
    expect(spec.fetch("servers").first.fetch("url")).to eq("http://localhost")
    operation = spec.dig("paths", "/api/v1/property_intakes", "post")
    expect(operation.fetch("security")).to eq([{ "BearerAuth" => [] }])
    expect(operation.fetch("responses")).to include("200", "201", "401", "409", "422")
    expect(operation.dig("requestBody", "content", "application/json", "example"))
      .to include("captador", "imovel", "proprietario")
  end
end
