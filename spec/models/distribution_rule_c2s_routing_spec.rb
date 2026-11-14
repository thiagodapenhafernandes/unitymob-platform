require "rails_helper"

RSpec.describe DistributionRule do
  it "traduz os tipos conhecidos e mantém texto livre somente em Outros" do
    rule = build(:distribution_rule, business_type: :locacao)
    expect(rule.c2s_routing_attributes(campaign: true)).to eq("source" => "Disparo de WhatsApp", "type_negotiation" => "Alugar")
    rule.assign_attributes(c2s_negotiation_type: "Compra", c2s_negotiation_other: "texto antigo", c2s_source: "  Campanha própria  ")
    expect(rule.c2s_routing_attributes).to eq("source" => "Campanha própria", "type_negotiation" => "Comprar")
    rule.c2s_negotiation_type = "Outros"
    expect(rule.c2s_routing_attributes).to eq("source" => "Campanha própria", "type_negotiation_string" => "texto antigo")
  end

  it "exige texto em Outros e rejeita tipo desconhecido" do
    rule = build(:distribution_rule, active: false, delivery_destination: "c2s", c2s_negotiation_type: "Outros")
    rule.valid?
    expect(rule.errors[:c2s_negotiation_other]).to be_present
    rule.c2s_negotiation_type = "Inválido"
    rule.valid?
    expect(rule.errors[:c2s_negotiation_type]).to be_present
  end

  it "não impõe fonte de campanha a regras de outros canais" do
    rule = build(:distribution_rule, business_type: :locacao)
    expect(rule.c2s_routing_attributes).to eq({})
  end
end
