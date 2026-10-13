require "rails_helper"

RSpec.describe MetaAi::ModelCatalog do
  describe ".response_model_options" do
    it "lista os modelos Muse curados e mantém o atual fora do catálogo" do
      options = described_class.response_model_options(selected: "muse-custom-test")

      expect(options).to include(["Muse Spark 1.3 · recomendado", "muse-spark-1.3"])
      expect(options).to include(["Atual: muse-custom-test", "muse-custom-test"])
      expect(options.last).to eq(["Personalizado", described_class::CUSTOM_VALUE])
    end
  end

  describe ".resolve_response_model" do
    it "resolve automático para o fallback operacional" do
      expect(described_class.resolve_response_model(described_class::AUTOMATIC_VALUE)).to eq(described_class::RESPONSE_FALLBACK_MODEL)
      expect(described_class.resolve_response_model("muse-spark-1.2")).to eq("muse-spark-1.2")
    end
  end

  describe ".resolve_transcription_model" do
    it "resolve automático para o fallback operacional de transcrição" do
      expect(described_class.resolve_transcription_model(described_class::AUTOMATIC_VALUE)).to eq(described_class::TRANSCRIPTION_FALLBACK_MODEL)
      expect(described_class.resolve_transcription_model("muse-voice-transcribe-1.0")).to eq("muse-voice-transcribe-1.0")
    end
  end

  describe ".fallback_response_model" do
    it "não sugere fallback quando o configurado já é o padrão" do
      expect(described_class.fallback_response_model(described_class::RESPONSE_FALLBACK_MODEL)).to be_nil
      expect(described_class.fallback_response_model("muse-wonder-1.0")).to eq(described_class::RESPONSE_FALLBACK_MODEL)
    end
  end
end
