require "rails_helper"

RSpec.describe DataHygiene::LocationValueSanitizer do
  it "normaliza variações de cidade e bairro em imóveis e endereços" do
    first = create(:habitation, codigo: "88#{SecureRandom.random_number(10**8)}", cidade: "Balneário  Camboriú ", bairro: "CENTRO")
    second = create(:habitation, codigo: "87#{SecureRandom.random_number(10**8)}", cidade: "Balneário Camboriú", bairro: "Centro")
    first.address.update!(cidade: "Balneário  Camboriú ", bairro: "CENTRO")
    second.address.update!(cidade: "Balneário Camboriú", bairro: "Centro")

    result = described_class.new(execute: true).call

    expect(result.updates).to be >= 2
    expect(first.reload.cidade).to eq("Balneário Camboriú")
    expect(first.bairro).to eq("Centro")
    expect(first.address.reload.cidade).to eq("Balneário Camboriú")
    expect(first.address.bairro).to eq("Centro")
  end

  it "corrige variações que diferem somente por espaços" do
    first = create(:habitation, codigo: "86#{SecureRandom.random_number(10**8)}", cidade: "Camboriú", bairro: "Tabuleiro")
    second = create(:habitation, codigo: "85#{SecureRandom.random_number(10**8)}", cidade: "Camboriú", bairro: "Tabuleiro")
    first.address.update!(cidade: "Camboriú ", bairro: "Tabuleiro ")
    second.address.update!(cidade: "Camboriú", bairro: "Tabuleiro")

    described_class.new(execute: true).call

    expect(first.address.reload.cidade).to eq("Camboriú")
    expect(first.address.bairro).to eq("Tabuleiro")
  end
end
