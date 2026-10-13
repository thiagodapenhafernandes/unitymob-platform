require "rails_helper"

RSpec.describe InterestIntelligence::Settings do
  describe ".normalize_settings" do
    it "limita números às faixas e converte salvaguardas para booleano" do
      normalized = described_class.normalize_settings(
        "max_suggestions" => "99",
        "minimum_match_score" => "-5",
        "broker_review_required" => "1",
        "allow_direct_lead_message" => "0",
        "unknown_key" => "x"
      )

      expect(normalized["max_suggestions"]).to eq(20)
      expect(normalized["minimum_match_score"]).to eq(0)
      expect(normalized["broker_review_required"]).to be(true)
      expect(normalized["allow_direct_lead_message"]).to be(false)
      expect(normalized).not_to have_key("unknown_key")
    end

    it "usa o padrão quando o valor é inválido" do
      normalized = described_class.normalize_settings("max_suggestions" => "abc")

      expect(normalized["max_suggestions"]).to eq(described_class::DEFAULTS["max_suggestions"])
    end
  end

  describe ".normalize_form_params" do
    it "anula instruções iguais ao padrão do sistema" do
      attributes = ActionController::Parameters.new(
        interest_intelligence_instructions: InterestIntelligence::SystemInstructions::DEFAULT_TEXT
      ).permit(:interest_intelligence_instructions, interest_intelligence_settings: {})

      described_class.normalize_form_params(attributes)

      expect(attributes[:interest_intelligence_instructions]).to be_nil
    end

    it "preserva instruções personalizadas" do
      attributes = ActionController::Parameters.new(
        interest_intelligence_instructions: "Diretriz da conta"
      ).permit(:interest_intelligence_instructions, interest_intelligence_settings: {})

      described_class.normalize_form_params(attributes)

      expect(attributes[:interest_intelligence_instructions]).to eq("Diretriz da conta")
    end
  end
end
