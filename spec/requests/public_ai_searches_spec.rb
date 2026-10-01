require "rails_helper"

# Busca por descrição/voz do hero: devolve só a URL da listagem com os filtros (nunca imóveis) e respeita todas as travas.
RSpec.describe "Busca por descrição (IA) do hero", type: :request do
  let(:tenant) { Tenant.default }
  let(:interpretation) do
    Ai::PropertySearch::Interpreter::Result.new(
      intent: "search_properties", filters: { "property_type" => "Apartamento", "city" => "Itajaí", "bedrooms_min" => 2, "price_max" => 3_000_000 },
      missing_required_information: [], clarifying_question: nil
    )
  end

  before do
    host! "localhost"
    Tenants::LocalPublicHostOverride.clear!
    Rails.cache.clear
    allow_any_instance_of(Ai::PropertySearch::Interpreter).to receive(:call).and_return(interpretation)
  end

  after { Tenants::LocalPublicHostOverride.clear! }

  def enable!(home: true, ai: true, voice: false)
    Setting.set(Ai::PropertyContentService::API_KEY_SETTING, "token", "Token", tenant:) if ai
    PropertySetting.instance(tenant:).update!(ai_property_search_enabled: ai, voice_property_search_enabled: voice)
    HomeSetting.instance(tenant:).update!(hero_layout: "card", hero_ai_search_enabled: home)
  end

  def post_search(params = {}) = post(public_ai_search_path, params: { query: "apartamento 2 quartos em Itajaí" }.merge(params), headers: { "Accept" => "application/json" })

  it "interpreta o texto e devolve a URL da listagem com os filtros traduzidos" do
    enable!

    post_search(transaction_type: "venda")

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    query = Rack::Utils.parse_nested_query(URI.parse(body["redirect_url"]).query)
    expect(URI.parse(body["redirect_url"]).path).to eq("/imoveis")
    expect(query).to include("transaction_type" => "venda", "category" => ["Apartamento"], "city" => ["Itajaí"], "min_bedrooms" => "2", "max_price" => "3000000", "v" => "2")
    expect(body["summary"]).to include("Tipo: Apartamento", "Quartos: 2+")
    expect(body["transcription"]).to eq("apartamento 2 quartos em Itajaí")
  end

  it "não responde quando a Home não liga o recurso ou a IA da conta não está pronta; vale em qualquer layout" do
    enable!(home: false)
    post_search
    expect(response).to have_http_status(:not_found)

    enable!(ai: false)
    post_search
    expect(response).to have_http_status(:not_found)

    enable!
    HomeSetting.instance(tenant:).update!(hero_layout: "classic")
    post_search
    expect(response).to have_http_status(:ok)
  end

  it "descrição vazia ou sem nenhum filtro entendido volta 422 com mensagem" do
    enable!
    post_search(query: "   ")
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to include("Descreva")

    allow_any_instance_of(Ai::PropertySearch::Interpreter).to receive(:call).and_return(interpretation.with(filters: {}))
    post_search
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to include("Não consegui entender")
  end

  it "falha da IA vira 502 genérico, sem vazar detalhes" do
    enable!
    allow_any_instance_of(Ai::PropertySearch::Interpreter).to receive(:call).and_raise(RuntimeError, "chave sk-secreta inválida")

    post_search

    expect(response).to have_http_status(:bad_gateway)
    expect(response.body).not_to include("sk-secreta")
  end

  it "limita o texto a 300 caracteres" do
    enable!
    captured = nil
    allow(Ai::PropertySearch::Interpreter).to receive(:new) { |**args| captured = args[:text]; instance_double(Ai::PropertySearch::Interpreter, call: interpretation) }

    post_search(query: "a" * 900)

    expect(captured.length).to eq(300)
  end

  describe "voz" do
    let(:audio) { Rack::Test::UploadedFile.new(StringIO.new("fake"), "audio/webm", original_filename: "busca.webm") }

    it "transcreve o áudio, interpreta e navega; o áudio não vira texto da requisição" do
      enable!(voice: true)
      allow_any_instance_of(Ai::PropertySearch::Transcriber).to receive(:call).and_return("apartamento em Itajaí")

      post public_ai_search_path, params: { audio: audio, audio_duration_seconds: "6" }, headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["transcription"]).to eq("apartamento em Itajaí")
    end

    it "recusa áudio longo, sem duração ou quando a voz está desligada na conta" do
      enable!(voice: true)
      post public_ai_search_path, params: { audio: audio, audio_duration_seconds: "45" }
      expect(response).to have_http_status(:unprocessable_entity)

      post public_ai_search_path, params: { audio: audio }
      expect(response).to have_http_status(:unprocessable_entity)

      enable!(voice: false)
      post public_ai_search_path, params: { audio: audio, audio_duration_seconds: "5" }
      expect(response).to have_http_status(:not_found)
    end
  end
end
