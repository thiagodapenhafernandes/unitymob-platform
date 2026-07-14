require "rails_helper"

RSpec.describe Ai::PropertySearch::DevelopmentResolver do
  let(:tenant) { Tenant.create!(name: "Busca IA #{SecureRandom.hex(3)}", slug: "busca-ia-#{SecureRandom.hex(4)}") }
  let(:setting) { PropertySetting.instance(tenant: tenant) }

  def development(name:, code:, tenant: self.tenant, neighborhood: "Barra da Tijuca", developer: "Cyrela")
    record = create(:habitation, tenant:, tipo: "Empreendimento", categoria: "Apartamento", codigo: code,
      nome_empreendimento: name, construtora: developer, bairro: neighborhood)
    record.address.update!(bairro: neighborhood, cidade: "Rio de Janeiro")
    record
  end

  it "resolve na ordem exata, alias, parcial e fuzzy sem atravessar tenant" do
    reserva = development(name: "Reserva do Parque", code: "DEV-RESERVA")
    DevelopmentAlias.create!(tenant:, development: reserva, name: "Residencial Reserva")
    other_tenant = Tenant.create!(name: "Outra busca IA #{SecureRandom.hex(3)}", slug: "outra-busca-ia-#{SecureRandom.hex(4)}")
    development(name: "Reserva de Outro Tenant", code: "DEV-OTHER", tenant: other_tenant)

    exact = described_class.new(tenant:, setting:, filters: { development_name: "Reserva do Parque" }).call
    aliased = described_class.new(tenant:, setting:, filters: { development_name: "Residencial Reserva" }).call
    partial = described_class.new(tenant:, setting:, filters: { development_name: "Parque" }).call
    fuzzy = described_class.new(tenant:, setting:, filters: { development_name: "Rezerva du Parqe" }).call

    expect([exact, aliased, partial, fuzzy]).to all(be_resolved)
    expect([exact, aliased, partial, fuzzy].map { |result| result.filters["_development_codes"] }).to all(eq(["DEV-RESERVA"]))
    expect([exact.match_type, aliased.match_type, partial.match_type, fuzzy.match_type]).to eq(%w[exact alias partial fuzzy])
  end

  it "retorna opções quando há mais de um empreendimento relevante" do
    development(name: "Reserva do Parque", code: "DEV-1")
    development(name: "Reserva Jardim", code: "DEV-2", neighborhood: "Jacarepaguá")

    result = described_class.new(tenant:, setting:, filters: { development_name: "Reserva" }).call

    expect(result).to be_ambiguous
    expect(result.candidates.map { |item| item[:name] }).to contain_exactly("Reserva do Parque", "Reserva Jardim")
  end

  it "identifica por incorporadora, localização, lançamento e características" do
    target = development(name: "Vivaz Parque Freguesia", code: "DEV-VIVAZ", neighborhood: "Freguesia", developer: "Vivaz")
    target.update!(lancamento_flag: true, infra_estrutura: ["Lazer completo"])

    result = described_class.new(tenant:, setting:, filters: {
      developer_name: "Vivaz", neighborhood: "Freguesia", property_condition: "launch", amenities: ["lazer completo"]
    }).call

    expect(result).to be_resolved
    expect(result.filters["_development_codes"]).to eq(["DEV-VIVAZ"])
    expect(result.match_type).to eq("characteristics")
  end
end
