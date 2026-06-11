require "rails_helper"

RSpec.describe "Habitation feature normalization" do
  it "normalizes obvious catalog labels when saving attribute options" do
    option = AttributeOption.create!(context: "habitation", category: "feature", name: "area_servico")
    infrastructure = AttributeOption.create!(context: "habitation", category: "infrastructure", name: "Portaria24 Hrs")

    expect(option.name).to eq("Área de serviço")
    expect(infrastructure.name).to eq("Portaria 24h")
  end

  it "normalizes property and infrastructure features for public display" do
    habitation = build(
      :habitation,
      caracteristicas: ["adega", "Area Servico", "area_servico", "banheiro_social"],
      infra_estrutura: ["Portaria24 Hrs", "Poco Artesiano", "Portaria 24h"]
    )

    expect(habitation.property_features_for_display).to eq(["Adega", "Área de serviço", "Banheiro social"])
    expect(habitation.leisure_features_for_display).to eq(["Portaria 24h", "Poço artesiano"])
  end
end
