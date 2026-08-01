require "rails_helper"

RSpec.describe "Admin::AiIntegrations", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza o workspace operacional de IA" do
    get admin_ai_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ai-integration-workspace")
    expect(response.body).to include("Conteúdo")
    expect(response.body).to include("Voice PWA")
    expect(response.body).to include("Configuração do provedor")
    expect(response.body).to include("Geração em lote")
    expect(response.body).to include("Token dedicado da OpenAI")
    expect(response.body).to include("Modelo de interpretação")
    expect(response.body).to include("Modelo de transcrição")
    expect(response.body).to include("ax-progress")
    expect(response.body).not_to include("progress-bar")
    progress = Nokogiri::HTML(response.body).at_css(".ax-progress progress.ax-progress__bar")
    expect(progress).to be_present
    expect(progress["max"]).to eq("100")
    expect(progress["style"]).to be_nil
  end

  it "salva configurações dedicadas do Voice PWA sem sobrescrever conteúdo" do
    Setting.set(Ai::PropertyContentService::PROMPT_SETTING, "Prompt de conteúdo", "Prompt", tenant: admin.tenant)

    with_forgery_protection_disabled do
      patch admin_ai_integration_path, params: {
        ai: {
          section: "voice_pwa",
          property_search_api_key: "voice-token",
          property_search_model: "gpt-4.1-mini",
          property_search_transcription_model: "gpt-4o-mini-transcribe"
        }
      }
    end

    expect(response).to redirect_to(admin_ai_integration_path(anchor: "ai-integration-voice"))
    expect(Setting.get(Ai::PropertySearch::Configuration::API_KEY_SETTING, nil, tenant: admin.tenant)).to eq("voice-token")
    expect(Setting.get(Ai::PropertySearch::Configuration::MODEL_SETTING, nil, tenant: admin.tenant)).to eq("gpt-4.1-mini")
    expect(Setting.get(Ai::PropertySearch::Configuration::TRANSCRIPTION_MODEL_SETTING, nil, tenant: admin.tenant)).to eq("gpt-4o-mini-transcribe")
    expect(Setting.get(Ai::PropertyContentService::PROMPT_SETTING, nil, tenant: admin.tenant)).to eq("Prompt de conteúdo")
  end

  def with_forgery_protection_disabled
    ActionController::Base.allow_forgery_protection = false
    yield
  ensure
    ActionController::Base.allow_forgery_protection = false
  end
end
