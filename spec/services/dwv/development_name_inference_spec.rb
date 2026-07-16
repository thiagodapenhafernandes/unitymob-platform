require "rails_helper"

RSpec.describe Dwv::DevelopmentNameInference do
  describe ".call" do
    it "reconhece nomes de empreendimento/residencial no complemento" do
      [
        "BOULEVARD DA BARRA PARK RESIDENCE",
        "Residencial Bosque dos Ipês",
        "Condomínio Bosque de Taquaras",
        "Villaggio Toscana",
        "Reserva do Vale",
        "ED. SAINT PAUL",       # abreviação de Edifício
        "Perico Residence",
        "Condominio Vila Rica"
      ].each do |text|
        expect(described_class.call(text)).to eq(text), "esperava reconhecer: #{text}"
      end
    end

    it "ignora localizadores de unidade e descritores genéricos" do
      [
        "Casa 2", "Apto 101", "Bloco B", "Lote 12", "Fundos", "Sala 402",
        "Condomínio Fechado", "Residencial", "Casa", "301", "Final 01",
        "Residencia 6",                        # residência + número => unidade
        "Apartamento 403 - Torre 1 (Jatobá)"   # unidade misturada com prédio
      ].each do |text|
        expect(described_class.call(text)).to be_nil, "não deveria reconhecer: #{text}"
      end
    end

    it "retorna o primeiro candidato válido preservando a grafia original" do
      expect(described_class.call("Casa 2", "Portal das Águas")).to eq("Portal das Águas")
    end

    it "retorna nil quando nenhum texto é fornecido" do
      expect(described_class.call(nil, "")).to be_nil
    end
  end
end
