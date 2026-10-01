require "rails_helper"

RSpec.describe Ai::PropertySearch::PublicParams do
  def params_for(filters, options = {}) = described_class.new(filters, **options).call

  it "traduz os filtros da IA para os parâmetros da listagem pública" do
    result = params_for({
      "transaction_type" => "rent", "property_type" => "Apartamento", "city" => "Itajaí", "neighborhood" => "Centro",
      "bedrooms_min" => 2, "suites_min" => 1, "parking_spaces_min" => 1, "private_area_min" => 80.0,
      "price_min" => 1_500_000, "price_max" => 2_000_000.0, "development_name" => "Residencial Sol", "property_condition" => "launch"
    })

    expect(result).to eq(
      "transaction_type" => "aluguel", "category" => ["Apartamento"], "city" => ["Centro - Itajaí"], "development" => ["Residencial Sol"],
      "min_bedrooms" => "2", "min_suites" => "1", "min_parking" => "1", "min_area" => "80",
      "min_price" => "1500000", "max_price" => "2000000", "characteristics" => ["lancamento_flag"]
    )
  end

  it "só cidade vira city; só bairro vira neighborhood; código vira a busca livre" do
    expect(params_for({ "city" => "Itajaí" })).to eq("city" => ["Itajaí"])
    expect(params_for({ "neighborhood" => "Centro" })).to eq("neighborhood" => "Centro")
    expect(params_for({ "property_code" => "AP123" })).to eq("search" => "AP123")
  end

  it "usa a finalidade da aba quando a descrição não diz e ignora o que a listagem não entende" do
    expect(params_for({ "city" => "Itajaí", "amenities" => ["piscina"], "bogus" => "x" }, { default_transaction: "aluguel" }))
      .to eq("transaction_type" => "aluguel", "city" => ["Itajaí"])
    expect(params_for({ "city" => "Itajaí" }, { default_transaction: "qualquer" })).to eq("city" => ["Itajaí"])
  end

  it "resume o que foi entendido" do
    summary = described_class.summary("property_type" => "Casa", "city" => "Itajaí", "bedrooms_min" => 3, "price_max" => 900_000)

    expect(summary).to eq(["Tipo: Casa", "Cidade: Itajaí", "Quartos: 3+", "Valor máximo: R$ 900.000"])
  end
end
