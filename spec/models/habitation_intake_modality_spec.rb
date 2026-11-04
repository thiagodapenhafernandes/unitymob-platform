require "rails_helper"

RSpec.describe Habitation do
  it "reconhece diária ao reabrir um imóvel sem modalidade de captação gravada" do
    property = build(:habitation, status: "Diária", intake_modalidade: nil)
    expect(property.modalidade).to eq("locacao_diaria")
  end

  it "mantém diária distinta de locação anual e preserva venda e o fluxo de divisão de ambos" do
    property = build(:habitation)
    { "locacao_diaria" => "Diária", "locacao_anual" => "Aluguel", "venda" => "Venda", "ambos" => "Venda" }.each do |modality, status|
      property.modalidade = modality
      expect(property.intake_modalidade).to eq(modality)
      expect(property.status).to eq(status)
    end
  end
end
