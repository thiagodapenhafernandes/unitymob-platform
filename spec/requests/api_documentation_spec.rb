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
  it "documenta todos os campos de captação e a busca autenticada" do
    get "/docs/openapi.yaml"
    contract = YAML.safe_load(response.body)
    property = contract.dig("components", "schemas", "Imovel")
    expect(property.fetch("required")).not_to include("titulo", "descricao")
    expect(property.dig("properties", "categoria", "enum")).to match_array(
      Habitation::CATEGORIES.map { |category| category.parameterize(separator: "_") }
    )
    expect(property.fetch("properties")).to include("torre", "demi_suites", "nome_condominio",
      "area_total_m2", "tipo_vaga", "box", "onde_estao_as_chaves", "permuta", "parcelamento",
      "administracao_locacao", "tipo_cadastro", "observacoes_internas", "observacoes_restritas",
      "caracteristicas_internas", "infraestrutura_lazer")
    expect(contract.dig("components", "schemas", "Captador", "properties")).to include("email")
    expect(contract.dig("components", "schemas", "Captacao", "properties")).to include("documentos")
    expect(contract.dig("paths", "/api/v1/properties/search", "get", "security")).to eq([{ "BearerAuth" => [] }])
  end

  it "documenta o catálogo autenticado, os tipos aceitos nas listas e o tipo de logradouro" do
    get "/docs/openapi.yaml"
    contract = YAML.safe_load(response.body)
    operation = contract.dig("paths", "/api/v1/property_features", "get")
    expect(operation.fetch("security")).to eq([{ "BearerAuth" => [] }])
    expect(operation.fetch("responses")).to include("200", "401")
    schema = operation.dig("responses", "200", "content", "application/json", "schema")
    expect(schema.fetch("required")).to match_array(%w[caracteristicas_internas infraestrutura_lazer])
    expect(contract.dig("components", "schemas", "ListaCaracteristicas", "items", "oneOf")
      .map { |item| item.fetch("type") }).to eq(%w[integer string])
    address = contract.dig("components", "schemas", "Endereco")
    expect(address.fetch("required")).not_to include("tipo_logradouro")
    expect(address.dig("properties", "tipo_logradouro", "type")).to eq("string")
  end

end
