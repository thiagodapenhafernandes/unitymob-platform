require "rails_helper"

RSpec.describe "Distribuição por modalidade e cidade" do
  let(:tenant) { Tenant.default }
  before { allow_any_instance_of(Lead).to receive(:route_lead) }

  def entry(city: nil, business: "rent", **attributes)
    build(:lead, tenant: tenant, origin: "site", attribution_data: { "business_type" => business },
      other_information: city ? { "interest_city" => city } : {}, **attributes)
  end

  it "combina modalidade E qualquer cidade, com igualdade sem distinção de acento/caixa" do
    rule = create(:distribution_rule, tenant: tenant, business_type: :locacao, property_cities: ["Itapema", "Balneário Camboriú"])
    [" itapema ", "BALNEARIO CAMBORIU"].each do |city|
      expect(Leads::DistributorService.new(entry(city: city)).send(:find_matching_rule)).to eq(rule)
    end
    [entry(city: "Porto Belo"), entry(city: "Itapema do Norte"), entry(city: "Itapema", business: "sale"), entry].each do |lead|
      expect(Leads::DistributorService.new(lead).send(:find_matching_rule)).to be_nil
    end
  end

  it "prioriza uma fila restrita elegível sobre uma geral e mantém o fallback para outra cidade" do
    general = create(:distribution_rule, tenant: tenant, business_type: :locacao)
    local = create(:distribution_rule, tenant: tenant, business_type: :locacao, property_cities: ["Itapema", "Porto Belo"])
    expect(Leads::DistributorService.new(entry(city: "Porto Belo")).send(:find_matching_rule)).to eq(local)
    expect(Leads::DistributorService.new(entry(city: "Florianópolis")).send(:find_matching_rule)).to eq(general)
  end

  it "usa o imóvel da consulta e não o endereço pessoal, respeitando o tenant" do
    property = create(:habitation, tenant: tenant)
    property.address.update!(cidade: "Itapema")
    lead = entry(city: "Porto Belo", property_id: property.id)
    expect(Leads::EntryLocation.city(lead)).to eq("Itapema")
    other = Tenant.create!(name: "Outra", slug: "city-#{SecureRandom.hex(4)}")
    lead.tenant = other
    lead.other_information = { "city" => "Itapema" }
    expect(Leads::EntryLocation.city(lead)).to be_nil
    foreign_rule = create(:distribution_rule, tenant: tenant, property_cities: ["Itapema"])
    expect(Leads::DistributorService.new(lead).send(:find_matching_rule)).not_to eq(foreign_rule)
  end

  it "classifica a nova consulta sem herdar a cidade do lead antigo" do
    rule = create(:distribution_rule, tenant: tenant, business_type: :locacao, property_cities: ["Porto Belo"])
    original = entry(city: "Itapema")
    inquiry = entry(city: "Porto Belo")
    expect(Leads::DistributorService.new(original, inquiry: inquiry).send(:find_matching_rule)).to eq(rule)
    expect(Leads::DistributorService.new(original, inquiry: entry).send(:find_matching_rule)).to be_nil
  end

  it "mantém os filtros genéricos em conjunto com a cidade e aceita a cidade do produto importado" do
    rule = create(:distribution_rule, tenant: tenant, property_cities: ["Itapema"], custom_filters: [{ "key" => "product", "value" => "Apartamento" }])
    lead = entry
    lead.attribution_data["product"] = { "city" => "Itapema" }
    lead.product = "Terreno"
    expect(Leads::DistributorService.new(lead).send(:find_matching_rule)).to be_nil
    lead.product = "Apartamento"
    expect(Leads::DistributorService.new(lead).send(:find_matching_rule)).to eq(rule)
    lead.attribution_data.delete("product")
    lead.other_information = { "external_lead_payload" => { "attributes" => "inválido" } }
    expect(Leads::EntryLocation.city(lead)).to be_nil
  end
end
