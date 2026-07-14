require "rails_helper"

RSpec.describe Ai::PropertySearch::LocationResolver do
  let(:tenant) { Tenant.default }
  let(:broker) { create(:admin_user, tenant: tenant) }
  let(:setting) { PropertySetting.instance(tenant: tenant) }

  def create_located_habitation(cidade:, bairro:, codigo:)
    habitation = create(:habitation, tenant:, admin_user: broker, categoria: "Apartamento", cidade:, codigo:)
    habitation.address.update!(cidade:, bairro:)
    habitation
  end

  it "corrige bairro transcrito errado usando similaridade" do
    create_located_habitation(cidade: "Itapema", bairro: "Meia Praia", codigo: "LOC-FUZZY")

    result = described_class.new(
      tenant:, setting:,
      filters: { "city" => "Itapema", "neighborhood" => "mea praia" }
    ).call

    expect(result.filters["neighborhood"]).to eq("Meia Praia")
    expect(result.corrections).to include(hash_including(field: "neighborhood", from: "mea praia", to: "Meia Praia"))
  end

  it "não corrige quando a similaridade fica abaixo do limiar" do
    create_located_habitation(cidade: "Itapema", bairro: "Meia Praia", codigo: "LOC-THRESHOLD")

    result = described_class.new(
      tenant:, setting:,
      filters: { "city" => "Itapema", "neighborhood" => "zona portuária norte" }
    ).call

    expect(result.filters["neighborhood"]).to eq("zona portuária norte")
    expect(result.corrections).to be_empty
  end

  it "normaliza cidade sem registrar correção quando só muda acentuação ou caixa" do
    create_located_habitation(cidade: "Itapema", bairro: "Centro", codigo: "LOC-CANONICAL")

    result = described_class.new(tenant:, setting:, filters: { "city" => "itapema" }).call

    expect(result.filters["city"]).to eq("Itapema")
    expect(result.corrections).to be_empty
  end

  it "restringe candidatos de bairro à cidade resolvida" do
    create_located_habitation(cidade: "Itapema", bairro: "Meia Praia", codigo: "LOC-CITY-A")
    create_located_habitation(cidade: "Porto Belo", bairro: "Perequê", codigo: "LOC-CITY-B")

    result = described_class.new(
      tenant:, setting:,
      filters: { "city" => "Porto Belo", "neighborhood" => "pereque" }
    ).call

    expect(result.filters["neighborhood"]).to eq("Perequê")
  end

  it "não usa localizações de outro tenant como candidatas" do
    outside_tenant = Tenant.create!(name: "Loc Resolver #{SecureRandom.hex(3)}", slug: "loc-resolver-#{SecureRandom.hex(3)}")
    outsider = create(:habitation, tenant: outside_tenant, categoria: "Apartamento", cidade: "Cidade Alheia", codigo: "LOC-OUTSIDE")
    outsider.address.update!(cidade: "Cidade Alheia", bairro: "Bairro Alheio")

    result = described_class.new(
      tenant:, setting:,
      filters: { "neighborhood" => "bairro alheio" }
    ).call

    expect(result.filters["neighborhood"]).to eq("bairro alheio")
    expect(result.corrections).to be_empty
  end

  it "respeita o toggle de fuzzy matching desligado" do
    create_located_habitation(cidade: "Itapema", bairro: "Meia Praia", codigo: "LOC-TOGGLE")
    setting.update!(ai_property_search_fuzzy_matching_enabled: false)

    result = described_class.new(
      tenant:, setting:,
      filters: { "city" => "Itapema", "neighborhood" => "mea praia" }
    ).call

    expect(result.filters["neighborhood"]).to eq("mea praia")
  end
end
