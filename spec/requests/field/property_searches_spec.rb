require "rails_helper"

RSpec.describe "Field::PropertySearches", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:mobile_headers) { { "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Mobile", "Accept" => "application/json" } }
  let(:broker) { create(:admin_user, :field_agent) }
  let(:setting) { PropertySetting.instance(tenant: broker.tenant) }

  before do
    host! "localhost"
    broker.profile.update!(permissions: Profile.default_permissions_for("Corretor"))
    setting.update!(ai_property_search_enabled: true, ai_property_search_history_enabled: true)
    sign_in broker
  end

  it "renderiza a busca no PWA somente quando perfil e feature estão autorizados" do
    setting.update!(voice_property_search_enabled: true)
    get field_root_path, headers: mobile_headers.except("Accept")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("field-ai-search-fab", "Buscar imóveis por voz", "voice=1")

    get field_property_search_path, headers: mobile_headers.except("Accept")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Busca inteligente", "field-property-search")
    expect(response.body).to include("Falar busca", "Descartar gravação", "Pausar gravação", "Enviar áudio")
    expect(response.body).to include("Transcrevendo, entendendo os filtros e procurando imóveis disponíveis")
  end

  it "remove o botão global quando a chave-mestra está desligada" do
    setting.update!(ai_property_search_enabled: false, voice_property_search_enabled: true)

    get field_root_path, headers: mobile_headers.except("Accept")

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("field-ai-search-fab")
  end

  it "interpreta filtros, consulta o escopo autorizado e registra histórico sem áudio" do
    property = create(:habitation, tenant: broker.tenant, admin_user: broker, codigo: "VOICE-SEARCH", categoria: "Apartamento", dormitorios_qtd: 3)
    interpretation = Ai::PropertySearch::Interpreter::Result.new(
      intent: "search_properties",
      filters: { "property_type" => "apartments", "bedrooms_min" => 3 },
      missing_required_information: [],
      clarifying_question: nil
    )
    interpreter = instance_double(Ai::PropertySearch::Interpreter, call: interpretation)
    allow(Ai::PropertySearch::Interpreter).to receive(:new).and_return(interpreter)

    post field_property_search_path(format: :json), params: { query: "Apartamentos com três quartos" }, headers: json_headers

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body
    expect(payload.fetch("results").map { |item| item["id"] }).to include(property.id)
    history = AiPropertySearchHistory.last
    expect(history).to have_attributes(tenant_id: broker.tenant_id, admin_user_id: broker.id, original_audio_reference: nil, status: "completed")
  end

  it "interpreta faixa falada como intervalo e não como valores soltos" do
    property = create(
      :habitation,
      tenant: broker.tenant,
      admin_user: broker,
      codigo: "VOICE-RANGE",
      categoria: "Apartamento",
      cidade: "Itapema",
      valor_venda_cents: 170_000_000,
      frente_mar_avenida_atlantica_flag: true
    )
    property.update!(cidade: "Itapema")
    property.address.update!(cidade: "Itapema", bairro: "Itapema")
    interpretation = Ai::PropertySearch::Interpreter::Result.new(
      intent: "search_properties",
      filters: { "property_type" => "apartments", "city" => "Itapema", "amenities" => ["Frente mar"], "price_min" => 1_500_000, "price_max" => 2_000_000 },
      missing_required_information: [],
      clarifying_question: nil
    )
    allow(Ai::PropertySearch::Interpreter).to receive(:new).and_return(instance_double(Ai::PropertySearch::Interpreter, call: interpretation))

    post field_property_search_path(format: :json), params: { query: "Quero apartamentos entre um milhão e meio e dois milhões, frente mar em Itapema." }, headers: json_headers

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body
    expect(payload.fetch("results").map { |item| item["id"] }).to include(property.id)
    expect(payload.fetch("results").first["price"]).to eq(1_700_000.0)
  end

  it "permite ao corretor consultar imóvel publicável de outro captador sem expor rota de edição" do
    other_broker = create(:admin_user, tenant: broker.tenant)
    property = create(:habitation, tenant: broker.tenant, admin_user: other_broker, codigo: "CATALOG-OTHER-BROKER", categoria: "Apartamento")
    interpretation = Ai::PropertySearch::Interpreter::Result.new(
      intent: "search_properties", filters: { "property_type" => "Apartamento" },
      missing_required_information: [], clarifying_question: nil
    )
    allow(Ai::PropertySearch::Interpreter).to receive(:new).and_return(instance_double(Ai::PropertySearch::Interpreter, call: interpretation))

    post field_property_search_path(format: :json), params: { query: "Apartamento" }, headers: json_headers

    item = response.parsed_body.fetch("results").find { |result| result["id"] == property.id }
    expect(item).to be_present
    expect(item.fetch("path")).to eq(admin_habitation_path(property))
    expect(item.fetch("preview_path")).to eq(property_preview_field_property_search_path(habitation_id: property.id))
  end

  it "renderiza preview server-side para abrir o detalhe no modal do PWA" do
    property = create(:habitation, tenant: broker.tenant, admin_user: broker, codigo: "MODAL-PREVIEW", categoria: "Apartamento")

    get property_preview_field_property_search_path(habitation_id: property.id), headers: mobile_headers.except("Accept")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("field-property-preview", "MODAL-PREVIEW", "Abrir cadastro completo")
  end

  it "executa a busca imediatamente mesmo quando a confirmação estava configurada" do
    setting.update!(ai_property_search_require_filter_confirmation: true)
    property = create(:habitation, tenant: broker.tenant, admin_user: broker, categoria: "Apartamento", codigo: "NO-CONFIRM")
    interpretation = Ai::PropertySearch::Interpreter::Result.new(intent: "search_properties", filters: { "property_type" => "Apartamento" }, missing_required_information: [], clarifying_question: nil)
    allow(Ai::PropertySearch::Interpreter).to receive(:new).and_return(instance_double(Ai::PropertySearch::Interpreter, call: interpretation))

    post field_property_search_path(format: :json), params: { query: "Imóvel em Itajaí" }, headers: json_headers

    expect(response.parsed_body.fetch("status")).to eq("completed")
    expect(response.parsed_body.fetch("results").map { |item| item["id"] }).to include(property.id)
  end

  it "busca unidades de todos os empreendimentos relevantes sem perguntar antes" do
    prefix = "DEV-#{SecureRandom.hex(4)}"
    first = create(:habitation, tenant: broker.tenant, tipo: "Empreendimento", nome_empreendimento: "#{prefix} Alpha", codigo: "DEV-1")
    second = create(:habitation, tenant: broker.tenant, tipo: "Empreendimento", nome_empreendimento: "#{prefix} Beta", codigo: "DEV-2")
    first_unit = create(:habitation, tenant: broker.tenant, admin_user: broker, codigo: "UNIT-1", codigo_empreendimento: first.codigo)
    second_unit = create(:habitation, tenant: broker.tenant, admin_user: broker, codigo: "UNIT-2", codigo_empreendimento: second.codigo)
    setting.update!(ai_property_search_development_name_enabled: true, ai_property_search_development_aliases_enabled: true)
    interpretation = Ai::PropertySearch::Interpreter::Result.new(intent: "search_properties", filters: { "development_name" => prefix }, missing_required_information: [], clarifying_question: nil)
    allow(Ai::PropertySearch::Interpreter).to receive(:new).and_return(instance_double(Ai::PropertySearch::Interpreter, call: interpretation))

    post field_property_search_path(format: :json), params: { query: "Quero no #{prefix}" }, headers: json_headers

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("status")).to eq("completed")
    result_ids = response.parsed_body.fetch("results").map { |item| item["id"] }
    expect(result_ids).to include(first_unit.id, second_unit.id)
  end

  it "ignora pergunta complementar da IA e executa a consulta" do
    property = create(:habitation, tenant: broker.tenant, admin_user: broker, categoria: "Apartamento", codigo: "IGNORE-QUESTION")
    interpretation = Ai::PropertySearch::Interpreter::Result.new(
      intent: "search_properties", filters: { "property_type" => "Apartamento" },
      missing_required_information: ["price"], clarifying_question: "Qual é a faixa de preço?"
    )
    allow(Ai::PropertySearch::Interpreter).to receive(:new).and_return(instance_double(Ai::PropertySearch::Interpreter, call: interpretation))

    post field_property_search_path(format: :json), params: { query: "Apartamento em Balneário Camboriú" }, headers: json_headers

    expect(response.parsed_body.fetch("status")).to eq("completed")
    expect(response.parsed_body.fetch("results").map { |item| item["id"] }).to include(property.id)
  end

  it "só sugere uma alternativa depois que a busca exata retorna zero" do
    setting.update!(ai_property_search_allow_flexible_results: true)
    alternative = create(:habitation, tenant: broker.tenant, admin_user: broker, categoria: "Apartamento", dormitorios_qtd: 4, cidade: "Cidade Exclusiva", codigo: "POST-ZERO-SUGGESTION")
    alternative.address.update!(cidade: "Cidade Exclusiva", bairro: "Bairro Exclusivo")
    interpretation = Ai::PropertySearch::Interpreter::Result.new(
      intent: "search_properties", filters: { "property_type" => "Apartamento", "bedrooms_min" => 5, "city" => "Cidade Exclusiva" },
      missing_required_information: [], clarifying_question: nil
    )
    allow(Ai::PropertySearch::Interpreter).to receive(:new).and_return(instance_double(Ai::PropertySearch::Interpreter, call: interpretation))

    post field_property_search_path(format: :json), params: { query: "Apartamento com cinco quartos na Cidade Exclusiva" }, headers: json_headers

    payload = response.parsed_body
    expect(response).to have_http_status(:ok)
    expect(payload.fetch("status")).to eq("completed")
    expect(payload.fetch("results")).to be_empty
    expect(payload.fetch("suggestions").map { |item| item["id"] }).to include(alternative.id)
    expect(payload.fetch("suggestion_message")).to include("Não houve correspondência exata")
    expect(payload.fetch("match_quality")).to eq("approximate")
    expect(payload.fetch("relaxed_criteria")).to include("quantities")
    expect(payload.fetch("relaxed_labels")).to be_present
  end

  it "busca resiliente sugere alternativas mesmo com a flexibilidade padrão desligada" do
    setting.update!(ai_property_search_allow_flexible_results: false, ai_property_search_resilient_search_enabled: true)
    alternative = create(:habitation, tenant: broker.tenant, admin_user: broker, categoria: "Apartamento", dormitorios_qtd: 4, cidade: "Cidade Garantida", codigo: "RESILIENT-REQUEST")
    alternative.address.update!(cidade: "Cidade Garantida", bairro: "Bairro Garantido")
    interpretation = Ai::PropertySearch::Interpreter::Result.new(
      intent: "search_properties", filters: { "property_type" => "Apartamento", "bedrooms_min" => 5, "city" => "Cidade Garantida", "neighborhood" => "Bairro Fantasma" },
      missing_required_information: [], clarifying_question: nil
    )
    allow(Ai::PropertySearch::Interpreter).to receive(:new).and_return(instance_double(Ai::PropertySearch::Interpreter, call: interpretation))

    post field_property_search_path(format: :json), params: { query: "Apartamento com cinco quartos no Bairro Fantasma da Cidade Garantida" }, headers: json_headers

    payload = response.parsed_body
    expect(response).to have_http_status(:ok)
    expect(payload.fetch("results")).to be_empty
    expect(payload.fetch("suggestions").map { |item| item["id"] }).to include(alternative.id)
    expect(payload.fetch("match_quality")).to eq("approximate")
    expect(payload.fetch("relaxed_criteria")).to match_array(%w[neighborhood quantities])
  end

  it "corrige cidade e bairro transcritos errado e informa a correção" do
    property = create(:habitation, tenant: broker.tenant, admin_user: broker, categoria: "Apartamento", cidade: "Itapema", codigo: "LOC-CORRECTION")
    property.address.update!(cidade: "Itapema", bairro: "Meia Praia")
    interpretation = Ai::PropertySearch::Interpreter::Result.new(
      intent: "search_properties", filters: { "property_type" => "Apartamento", "city" => "Itapema", "neighborhood" => "mea praia" },
      missing_required_information: [], clarifying_question: nil
    )
    allow(Ai::PropertySearch::Interpreter).to receive(:new).and_return(instance_double(Ai::PropertySearch::Interpreter, call: interpretation))

    post field_property_search_path(format: :json), params: { query: "Apartamento na mea praia em Itapema" }, headers: json_headers

    payload = response.parsed_body
    expect(response).to have_http_status(:ok)
    expect(payload.fetch("results").map { |item| item["id"] }).to include(property.id)
    expect(payload.fetch("match_quality")).to eq("exact")
    expect(payload.fetch("location_corrections")).to include(hash_including("field" => "neighborhood", "to" => "Meia Praia"))
  end

  it "bloqueia alternativas aproximadas quando a flexibilidade é desativada" do
    setting.update!(ai_property_search_allow_flexible_results: false, ai_property_search_resilient_search_enabled: false)
    alternative = create(:habitation, tenant: broker.tenant, admin_user: broker, categoria: "Apartamento", dormitorios_qtd: 4, cidade: "Cidade Flexível", valor_venda_cents: 3_100_000_00, codigo: "POST-RESILIENT-SUGGESTION")
    alternative.address.update!(cidade: "Cidade Flexível", bairro: "Bairro Flexível")
    interpretation = Ai::PropertySearch::Interpreter::Result.new(
      intent: "search_properties", filters: { "property_type" => "Apartamento", "bedrooms_min" => 5, "city" => "Cidade Flexível", "price_max" => 3_000_000 },
      missing_required_information: [], clarifying_question: nil
    )
    allow(Ai::PropertySearch::Interpreter).to receive(:new).and_return(instance_double(Ai::PropertySearch::Interpreter, call: interpretation))

    post field_property_search_path(format: :json), params: { query: "Buscar apartamento no valor de três milhões em Balneário Camboriú" }, headers: json_headers

    payload = response.parsed_body
    expect(response).to have_http_status(:ok)
    expect(payload.fetch("status")).to eq("completed")
    expect(payload.fetch("results")).to be_empty
    expect(payload.fetch("suggestions").map { |item| item["id"] }).not_to include(alternative.id)
  end

  it "bloqueia áudio quando a busca por voz está desativada" do
    setting.update!(voice_property_search_enabled: false)
    file = Tempfile.new(["busca", ".webm"])
    file.write("audio")
    file.rewind
    audio = Rack::Test::UploadedFile.new(file.path, "audio/webm", original_filename: "busca.webm")

    post field_property_search_path(format: :json), params: { audio:, audio_duration_seconds: 2 }, headers: json_headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("error")).to include("voz desativada")
  end

  it "nega perfis removidos da configuração" do
    setting.update!(ai_property_search_allowed_profiles: ["account_owner"])

    get field_property_search_path(format: :json), headers: mobile_headers

    expect(response).to have_http_status(:forbidden)
  end

  def json_headers
    mobile_headers.merge("X-CSRF-Token" => csrf_token)
  end

  def csrf_token
    get field_property_search_path, headers: mobile_headers.except("Accept")
    Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')&.[]("content")
  end
end
