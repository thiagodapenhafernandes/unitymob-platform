require "rails_helper"

RSpec.describe Ai::PropertySearch::SpecificRequest do
  let(:tenant) { Tenant.create!(name: "Busca Específica #{SecureRandom.hex(3)}", slug: "busca-especifica-#{SecureRandom.hex(4)}") }
  let(:setting) { PropertySetting.instance(tenant:) }

  it "extrai código explícito de imóvel e descarta filtros abrangentes interpretados" do
    result = described_class.new(
      setting:,
      text: "código do imóvel 9345",
      interpreted_filters: { "property_type" => "Apartamento", "bedrooms_min" => 9 }
    ).call

    expect(result.exact).to eq(true)
    expect(result.filters).to eq("property_code" => "9345")
  end

  it "trata uma busca composta apenas por referência numérica como código" do
    result = described_class.new(setting:, text: "9345", interpreted_filters: {}).call

    expect(result.exact).to eq(true)
    expect(result.filters).to eq("property_code" => "9345")
  end

  it "extrai nome de edifício como busca específica por empreendimento" do
    result = described_class.new(
      setting:,
      text: "edifício Adminirá",
      interpreted_filters: { "transaction_type" => "sale", "property_type" => "Apartamento", "bedrooms_min" => 4 }
    ).call

    expect(result.exact).to eq(true)
    expect(result.filters).to eq(
      "development_name" => "Adminirá"
    )
  end

  it "trata property_code interpretado pela IA como busca específica" do
    result = described_class.new(
      setting:,
      text: "buscar a referência falada",
      interpreted_filters: { "property_code" => "9345", "property_type" => "Apartamento" }
    ).call

    expect(result.exact).to eq(true)
    expect(result.filters).to eq("property_code" => "9345")
  end

  it "trata development_name interpretado pela IA como busca específica" do
    result = described_class.new(
      setting:,
      text: "Admirar com 2 vagas",
      interpreted_filters: { "development_name" => "Admirar", "property_type" => "Apartamento", "parking_spaces_min" => 2 }
    ).call

    expect(result.exact).to eq(true)
    expect(result.filters).to eq(
      "development_name" => "Admirar",
      "parking_spaces_min" => 2
    )
  end

  it "reconhece nome puro de empreendimento existente no catálogo do tenant" do
    create(
      :habitation,
      tenant:,
      codigo: "UNIT-AQUALINA",
      nome_empreendimento: "Aqualina Residence",
      categoria: "Apartamento"
    )

    result = described_class.new(setting:, tenant:, text: "Aqualina Residence.", interpreted_filters: {}).call

    expect(result.exact).to eq(true)
    expect(result.filters).to eq("development_name" => "Aqualina Residence")
  end

  it "trata texto curto com sufixo de edifício como busca específica mesmo sem catálogo" do
    result = described_class.new(setting:, tenant:, text: "Residence inexistente xyz", interpreted_filters: {}).call

    expect(result.exact).to eq(true)
    expect(result.filters).to eq("development_name" => "Residence inexistente xyz")
  end

  it "não trata características genéricas como nome de empreendimento sem sinal específico" do
    result = described_class.new(setting:, tenant:, text: "frente mar", interpreted_filters: {}).call

    expect(result.exact).to eq(false)
    expect(result.filters).to eq({})
  end

  it "não confunde taxa de condomínio com nome de condomínio" do
    result = described_class.new(
      setting:,
      text: "apartamento com condomínio até 800 reais",
      interpreted_filters: { "property_type" => "Apartamento", "condominium_fee_max" => 800 }
    ).call

    expect(result.exact).to eq(false)
    expect(result.filters).to include("property_type" => "Apartamento", "condominium_fee_max" => 800.0)
  end
end
