require "rails_helper"

RSpec.describe Ai::PropertySearch::ContextualFilters do
  let(:setting) { PropertySetting.instance }

  it "complementa os filtros quando já existe uma busca" do
    result = described_class.new(setting:, text: "agora com piscina", current_filters: { bedrooms_min: 3 }, interpreted_filters: { amenities: ["piscina"] }).call
    expect(result.mode).to eq("refine")
    expect(result.filters).to include("bedrooms_min" => 3, "amenities" => ["piscina"])
  end

  it "descarta o contexto quando o corretor pede nova busca" do
    result = described_class.new(setting:, text: "nova busca, casa em Itajaí", current_filters: { bedrooms_min: 3 }, interpreted_filters: { property_type: "Casa" }).call
    expect(result.mode).to eq("new")
    expect(result.filters).to eq("property_type" => "Casa")
  end

  it "remove explicitamente um critério da busca anterior" do
    result = described_class.new(setting:, text: "tira o frente mar e mantém a pesquisa", current_filters: { bedrooms_min: 4, amenities: ["frente mar"] }, interpreted_filters: {}).call
    expect(result.filters).to eq("bedrooms_min" => 4)
  end
end
