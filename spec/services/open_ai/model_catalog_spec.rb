require "rails_helper"

RSpec.describe OpenAi::ModelCatalog do
  describe ".response_model_options" do
    it "mantem o modelo atual no select mesmo quando não está no catálogo local" do
      options = described_class.response_model_options(selected: "gpt-custom-test")

      expect(options).to include(["Atual: gpt-custom-test", "gpt-custom-test"])
      expect(options.last).to eq(["Personalizado", described_class::CUSTOM_VALUE])
    end
  end

  describe ".resolve_response_model" do
    it "resolve automático para o fallback operacional" do
      expect(described_class.resolve_response_model(described_class::AUTOMATIC_VALUE)).to eq(described_class::RESPONSE_FALLBACK_MODEL)
      expect(described_class.resolve_response_model("gpt-custom-test")).to eq("gpt-custom-test")
    end
  end

  describe ".resolve_transcription_model" do
    it "resolve automático para o fallback operacional de transcrição" do
      expect(described_class.resolve_transcription_model(described_class::AUTOMATIC_VALUE)).to eq(described_class::TRANSCRIPTION_FALLBACK_MODEL)
      expect(described_class.resolve_transcription_model("whisper-1")).to eq("whisper-1")
    end
  end
end
