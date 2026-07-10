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

    it "inclui o nono dígito em celular brasileiro antigo com DDD" do
      expect(described_class.call("47 9972-9441")).to eq("5547999729441")
    end

    it "inclui o nono dígito em celular brasileiro antigo sem DDD" do
      expect(described_class.call("99729441")).to eq("999729441")
    end

    it "não inclui nono dígito em telefone fixo brasileiro" do
      expect(described_class.call("47 3311-1067")).to eq("554733111067")
    end

    it "remove placeholders zerados" do
      expect(described_class.call("00 00000-0000")).to be_nil
    end
  end

  describe ".display" do
    it "formata telefone brasileiro canônico" do
      expect(described_class.display("5547996158980")).to eq("55 (47) 99615-8980")
    end
  end
end
