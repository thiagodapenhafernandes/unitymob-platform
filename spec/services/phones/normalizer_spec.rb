# frozen_string_literal: true

require "rails_helper"

RSpec.describe Phones::Normalizer do
  describe ".call" do
    it "normaliza número brasileiro nacional para E.164 sem sinal de +" do
      expect(described_class.call("(47) 99615-8980")).to eq("5547996158980")
    end

    it "mantém número internacional informado com +" do
      expect(described_class.call("+1 (212) 555-0100")).to eq("12125550100")
    end

    it "remove placeholders zerados" do
      expect(described_class.call("00 00000-0000")).to be_nil
    end
  end

  describe ".display" do
    it "formata telefone brasileiro canônico" do
      expect(described_class.display("5547996158980")).to eq("+55 (47) 99615-8980")
    end
  end
end
