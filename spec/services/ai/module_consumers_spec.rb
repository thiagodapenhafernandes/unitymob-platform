require "rails_helper"

RSpec.describe "Consumidores dos vínculos de IA" do
  let(:tenant) { create(:admin_user, :admin).tenant }
  let(:client) { instance_double(MetaAi::Client) }

  def bind!(key, model)
    Setting.set(Ai::Provider::MUSE_API_KEY_SETTING, "meta-general", tenant: tenant)
    Setting.set(Ai::Provider::MUSE_VOICE_API_KEY_SETTING, "meta-voice", tenant: tenant)
    Ai::ModuleConfiguration.save!({ key => { "provider" => "muse", "model" => model } }, tenant: tenant)
  end

  it "gera conteúdo e SEO com seus próprios modelos e o cliente do provedor vinculado" do
    property = create(:habitation, tenant: tenant)
    bind!("property_content", "muse-property")
    bind!("seo", "muse-seo")
    expect(MetaAi::Client).to receive(:new).with(api_key: "meta-general").twice.and_return(client)
    expect(client).to receive(:create_response).with(hash_including(model: "muse-property"), fallback_model: "muse-spark-1.3").and_return(
      "output_text" => { title: "Título real", description: "Descrição real", seo_keywords: [] }.to_json
    )
    expect(client).to receive(:create_response).with(hash_including(model: "muse-seo"), fallback_model: "muse-spark-1.3").and_return(
      "output_text" => { meta_title: "SEO", meta_description: "Descrição SEO", keywords: [], intro_text: "Texto", insights: [] }.to_json
    )
    expect(Ai::PropertyContentService.new(property).send(:request_generation)).to include("title" => "Título real")
    seo = SeoSetting.new(tenant: tenant)
    expect(Ai::SeoContentService.new(seo).send(:request_generation)).to include("meta_title" => "SEO")
  end

  it "busca textual continua em OpenAI e interpretação de voz usa o vínculo de voz" do
    bind!("property_search_voice", "muse-voice-interpretation")
    setting = PropertySetting.instance(tenant: tenant)
    output = { intent: "search_properties", filters: {}, missing_required_information: [], clarifying_question: nil }.to_json
    openai_client = instance_double(OpenAi::Client)
    expect(OpenAi::Client).to receive(:new).and_return(openai_client)
    expect(openai_client).to receive(:create_response).with(hash_including(model: Ai::PropertyContentService::DEFAULT_MODEL), fallback_model: nil).and_return("output_text" => output)
    expect(MetaAi::Client).to receive(:new).with(api_key: "meta-voice").and_return(client)
    expect(client).to receive(:create_response).with(hash_including(model: "muse-voice-interpretation"), fallback_model: "muse-spark-1.3").and_return("output_text" => output)
    Ai::PropertySearch::Interpreter.new(setting: setting, text: "apartamento").call
    Ai::PropertySearch::Interpreter.new(setting: setting, text: "apartamento", voice: true).call
  end

  it "transcreve com token e modelo do vínculo de transcrição sem mudar a interpretação" do
    bind!("property_search_transcription", "muse-transcription")
    setting = PropertySetting.instance(tenant: tenant)
    setting.update!(voice_property_search_enabled: true)
    audio = Rack::Test::UploadedFile.new(StringIO.new("audio"), "audio/webm", original_filename: "busca.webm")
    expect(MetaAi::Client).to receive(:new).with(api_key: "meta-voice").and_return(client)
    expect(client).to receive(:transcribe).with(hash_including(file: audio, model: "muse-transcription", fallback_model: "muse-voice-transcribe-1.0")).and_return("Apartamento no centro")
    expect(Ai::PropertySearch::Transcriber.new(setting: setting, audio: audio).call).to eq("Apartamento no centro")
    expect(Ai::PropertySearch::Configuration.model(tenant: tenant)).to eq(Ai::PropertyContentService::DEFAULT_MODEL)
  end

  it "resume interesse com o vínculo de Leads mesmo sem conteúdo conectado" do
    bind!("interest_summary", "muse-interest")
    lead = create(:lead, tenant: tenant)
    expect(MetaAi::Client).to receive(:new).with(api_key: "meta-general").and_return(client)
    expect(client).to receive(:create_response).with(hash_including(model: "muse-interest"), fallback_model: "muse-spark-1.3").and_return("output_text" => { summary: "Resumo do lead" }.to_json)
    expect(InterestIntelligence::AiSummary.call(lead, profile: { confidence: 30 }, matches: [])).to include("summary" => "Resumo do lead")
    expect(Ai::PropertyContentService.connected?(tenant: tenant)).to be(false)
  end

  it "diagnostica com vínculo do BI e invalida cache ao trocar modelo, mantendo o histórico de uso" do
    bind!("dashboard_diagnosis", "muse-bi")
    Setting.set(Dashboard::AiDiagnosis::ENABLED_SETTING, "true", tenant: tenant)
    Setting.set(Dashboard::AiDiagnosis::WEEKLY_REQUEST_LIMIT_SETTING, "3", tenant: tenant)
    expect(MetaAi::Client).to receive(:new).with(api_key: "meta-general").twice.and_return(client)
    expect(client).to receive(:create_response).with(hash_including(model: "muse-bi"), fallback_model: "muse-spark-1.3").and_return("output_text" => { title: "BI", summary: "Primeiro modelo", recommendations: [], rationale: [] }.to_json)
    result = Dashboard::AiDiagnosis.new(tenant: tenant, period: 7, metrics: {}).call
    expect(result[:summary]).to eq("Primeiro modelo")
    cached = Dashboard::AiDiagnosis.new(tenant: tenant, period: 7, metrics: {}).call
    expect(cached[:source]).to eq("openai_cache")
    bind!("dashboard_diagnosis", "muse-bi-2")
    expect(client).to receive(:create_response).with(hash_including(model: "muse-bi-2"), fallback_model: "muse-spark-1.3").and_return("output_text" => { title: "BI", summary: "Segundo modelo", recommendations: [], rationale: [] }.to_json)
    expect(Dashboard::AiDiagnosis.new(tenant: tenant, period: 7, metrics: {}).call[:summary]).to eq("Segundo modelo")
    expect(OpenAiUsageEvent.where(tenant: tenant, feature: Dashboard::AiDiagnosis::FEATURE).count).to eq(2)
    expect(OpenAiUsageEvent.where(tenant: tenant).last.metadata["provider"]).to eq("muse")
  end
end
