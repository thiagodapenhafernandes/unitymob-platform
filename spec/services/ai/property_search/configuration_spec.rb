require "rails_helper"

RSpec.describe Ai::PropertySearch::Configuration do
  let(:tenant) { Tenant.create!(name: "Voice #{SecureRandom.hex(3)}", slug: "voice-#{SecureRandom.hex(4)}") }

  it "usa o token geral quando não há token dedicado" do
    Setting.set(Ai::PropertyContentService::API_KEY_SETTING, "general-token", "Token geral", tenant:)

    expect(described_class.api_key(tenant:)).to eq("general-token")
    expect(described_class.dedicated_api_key_configured?(tenant:)).to be(false)
    expect(described_class.connected?(tenant:)).to be(true)
  end

  it "prioriza token e modelos dedicados do Voice PWA" do
    Setting.set(Ai::PropertyContentService::API_KEY_SETTING, "general-token", "Token geral", tenant:)
    Setting.set(described_class::API_KEY_SETTING, "voice-token", "Token voice", tenant:)
    Setting.set(described_class::MODEL_SETTING, "gpt-4.1-mini", "Modelo voice", tenant:)
    Setting.set(described_class::TRANSCRIPTION_MODEL_SETTING, "gpt-4o-mini-transcribe", "Modelo transcrição", tenant:)

    expect(described_class.api_key(tenant:)).to eq("voice-token")
    expect(described_class.dedicated_api_key_configured?(tenant:)).to be(true)
    expect(described_class.model(tenant:)).to eq("gpt-4.1-mini")
    expect(described_class.transcription_model(tenant:)).to eq("gpt-4o-mini-transcribe")
  end

  it "resolve modelos automáticos para os fallbacks operacionais" do
    Setting.set(Ai::PropertyContentService::MODEL_SETTING, OpenAi::ModelCatalog::AUTOMATIC_VALUE, "Modelo geral", tenant:)
    Setting.set(described_class::MODEL_SETTING, OpenAi::ModelCatalog::AUTOMATIC_VALUE, "Modelo voice", tenant:)
    Setting.set(described_class::TRANSCRIPTION_MODEL_SETTING, OpenAi::ModelCatalog::AUTOMATIC_VALUE, "Modelo transcrição", tenant:)

    expect(Ai::PropertyContentService.model(tenant:)).to eq(OpenAi::ModelCatalog::AUTOMATIC_VALUE)
    expect(Ai::PropertyContentService.resolved_model(tenant:)).to eq(OpenAi::ModelCatalog::RESPONSE_FALLBACK_MODEL)
    expect(described_class.resolved_model(tenant:)).to eq(OpenAi::ModelCatalog::RESPONSE_FALLBACK_MODEL)
    expect(described_class.resolved_transcription_model(tenant:)).to eq(OpenAi::ModelCatalog::TRANSCRIPTION_FALLBACK_MODEL)
  end
end
