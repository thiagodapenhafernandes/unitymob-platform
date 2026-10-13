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
    expect(response.body).to include("Provedor de IA ativo")
    expect(response.body).to include("Token OpenAI")
    expect(response.body).to include("Token Meta Muse")
    expect(response.body).to include("Geração em lote")
    expect(response.body).to include("Modelo de interpretação")
    expect(response.body).to include("Modelo de transcrição")
    expect(response.body).to include("Diagnóstico textual do dashboard")
    expect(response.body).to include("Parâmetros da resposta")
    expect(response.body).to include("Temperature", "Top P", "Frequency penalty", "Presence penalty")
    expect(response.body).to include("Limite semanal de diagnósticos")
    expect(response.body).to include("Teto mensal estimado em centavos")
    expect(response.body).to include("Automático recomendado")
    expect(response.body).to include("Modelo personalizado")
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
          providers: {
            openai: {
              voice_api_key: "voice-token",
              voice_model_choice: Ai::Provider::CUSTOM_VALUE,
              voice_model_custom: "gpt-4.1-mini",
              voice_transcription_model_choice: "gpt-4o-mini-transcribe"
            }
          }
        }
      }
    end

    expect(response).to redirect_to(admin_ai_integration_path(anchor: "ai-integration-voice"))
    expect(Setting.get(Ai::PropertySearch::Configuration::API_KEY_SETTING, nil, tenant: admin.tenant)).to eq("voice-token")
    expect(Setting.get(Ai::PropertySearch::Configuration::MODEL_SETTING, nil, tenant: admin.tenant)).to eq("gpt-4.1-mini")
    expect(Setting.get(Ai::PropertySearch::Configuration::TRANSCRIPTION_MODEL_SETTING, nil, tenant: admin.tenant)).to eq("gpt-4o-mini-transcribe")
    expect(Setting.get(Ai::PropertyContentService::PROMPT_SETTING, nil, tenant: admin.tenant)).to eq("Prompt de conteúdo")
  end

  it "salva modelo automático e modelo personalizado de conteúdo" do
    with_forgery_protection_disabled do
      patch admin_ai_integration_path, params: {
        ai: {
          section: "content",
          providers: {
            openai: {
              api_key: "general-token",
              model_choice: Ai::Provider::CUSTOM_VALUE,
              model_custom: "gpt-custom-test"
            }
          },
          property_enrichment_prompt: "Prompt customizado",
          temperature: "0.2",
          top_p: "0.8",
          frequency_penalty: "0.5",
          presence_penalty: "0.2",
          dashboard_diagnosis_enabled: "1",
          dashboard_diagnosis_weekly_limit: "2",
          dashboard_diagnosis_monthly_budget_cents: "2500"
        }
      }
    end

    expect(response).to redirect_to(admin_ai_integration_path)
    expect(Setting.get(Ai::PropertyContentService::API_KEY_SETTING, nil, tenant: admin.tenant)).to eq("general-token")
    expect(Setting.get(Ai::PropertyContentService::MODEL_SETTING, nil, tenant: admin.tenant)).to eq("gpt-custom-test")
    expect(Setting.get(Ai::PropertyContentService::PROMPT_SETTING, nil, tenant: admin.tenant)).to eq("Prompt customizado")
    expect(Ai::PropertyContentService.response_parameters(tenant: admin.tenant)).to include(
      temperature: 0.2,
      top_p: 0.8,
      frequency_penalty: 0.5,
      presence_penalty: 0.2
    )
    expect(Setting.get(Dashboard::AiDiagnosis::ENABLED_SETTING, nil, tenant: admin.tenant)).to eq("true")
    expect(Setting.get(Dashboard::AiDiagnosis::WEEKLY_REQUEST_LIMIT_SETTING, nil, tenant: admin.tenant)).to eq("2")
    expect(Setting.get(Dashboard::AiDiagnosis::MONTHLY_BUDGET_CENTS_SETTING, nil, tenant: admin.tenant)).to eq("2500")

    with_forgery_protection_disabled do
      patch admin_ai_integration_path, params: {
        ai: {
          section: "content",
          providers: {
            openai: {
              model_choice: Ai::Provider::AUTOMATIC_VALUE
            }
          },
          property_enrichment_prompt: "Prompt automático"
        }
      }
    end

    expect(Setting.get(Ai::PropertyContentService::MODEL_SETTING, nil, tenant: admin.tenant)).to eq(Ai::Provider::AUTOMATIC_VALUE)
    expect(Ai::PropertyContentService.resolved_model(tenant: admin.tenant)).to eq(OpenAi::ModelCatalog::RESPONSE_FALLBACK_MODEL)
  end

  it "ativa Meta Muse e salva credenciais do provedor" do
    with_forgery_protection_disabled do
      patch admin_ai_integration_path, params: {
        ai: { section: "provider", provider: "muse" }
      }
    end

    expect(response).to redirect_to(admin_ai_integration_path)
    expect(Ai::Provider.active_key(tenant: admin.tenant)).to eq("muse")

    with_forgery_protection_disabled do
      patch admin_ai_integration_path, params: {
        ai: {
          section: "content",
          providers: {
            muse: {
              api_key: "meta-token",
              model_choice: "muse-spark-1.2"
            }
          },
          property_enrichment_prompt: "Prompt"
        }
      }
    end

    expect(Setting.get(Ai::Provider::MUSE_API_KEY_SETTING, nil, tenant: admin.tenant)).to eq("meta-token")
    expect(Setting.get(Ai::Provider::MUSE_MODEL_SETTING, nil, tenant: admin.tenant)).to eq("muse-spark-1.2")
    expect(Ai::PropertyContentService.api_key(tenant: admin.tenant)).to eq("meta-token")
    expect(Ai::PropertyContentService.resolved_model(tenant: admin.tenant)).to eq("muse-spark-1.2")
  end

  def with_forgery_protection_disabled
    ActionController::Base.allow_forgery_protection = false
    yield
  ensure
    ActionController::Base.allow_forgery_protection = false
  end
end
