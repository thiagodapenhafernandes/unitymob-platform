require "rails_helper"

RSpec.describe Habitations::AmenityFilter do
  let(:tenant) { Tenant.default }
  let(:scope) { Habitation.where(tenant_id: tenant.id) }

  it "finds accented infrastructure with accented or unaccented search terms" do
    property = create(:habitation, tenant: tenant, infra_estrutura: ["Salão de festas", "Salão de jogos"])

    ["Salão de festas", "Salao de festas", "SALÃO DE JOGOS"].each do |term|
      expect(described_class.call(scope, term)).to include(property)
    end
  end

  it "continues matching unaccented text and excludes properties without the item" do
    property = create(:habitation, tenant: tenant)
    property.update_columns(infra_estrutura: ["Salao de festas"])
    other = create(:habitation, tenant: tenant, infra_estrutura: ["Academia"])

    results = described_class.call(scope, "Salão de festas")
    expect(results).to include(property)
    expect(results).not_to include(other)
  end

  it "requires all selected items and preserves the supplied property scope" do
    complete = create(:habitation, tenant: tenant, infra_estrutura: ["Salão de festas", "Salão de jogos", "Piscina coletiva"], varanda_gourmet_flag: true)
    incomplete = create(:habitation, tenant: tenant, infra_estrutura: ["Salão de festas"])
    excluded = create(:habitation, tenant: tenant, infra_estrutura: ["Salão de festas", "Salão de jogos", "Piscina coletiva"], varanda_gourmet_flag: true)
    results = scope.where(id: [complete.id, incomplete.id])
    ["Sacada com churrasqueira a carvão", "Piscina coletiva", "Salão de festas", "Salão de jogos"].each do |term|
      results = described_class.call(results, term)
    end

    expect(results.pluck(:id)).to eq([complete.id])
    expect(results).not_to include(excluded)
  end

  it "finds service elevators recorded as infrastructure without a numeric count" do
    service = create(:habitation, tenant: tenant, elevadores_qtd: 0, infra_estrutura: ["Elevador de serviço"])
    numeric = create(:habitation, tenant: tenant, elevadores_qtd: 2, infra_estrutura: [])
    social = create(:habitation, tenant: tenant, elevadores_qtd: 0, infra_estrutura: ["Elevador social"])

    expect(described_class.call(scope, "Elevador de servico")).to contain_exactly(service)
    expect(described_class.call(scope, "Elevador")).to contain_exactly(service, numeric, social)
  end

  it "distinguishes pool types and does not treat a hot tub as a pool" do
    collective = create(:habitation, tenant: tenant, piscina_flag: false, infra_estrutura: ["Piscina coletiva"])
    heated = create(:habitation, tenant: tenant, piscina_flag: false, infra_estrutura: ["Piscina aquecida"])
    generic = create(:habitation, tenant: tenant, piscina_flag: true, infra_estrutura: [])
    characteristic = create(:habitation, tenant: tenant, piscina_flag: false, caracteristicas: {"Piscina" => "Piscina"})
    hot_tub = create(:habitation, tenant: tenant, piscina_flag: false, hidromassagem_qtd: 1, infra_estrutura: [])

    expect(described_class.call(scope, "Piscina coletiva")).to contain_exactly(collective)
    expect(described_class.call(scope, "Piscina aquecida")).to contain_exactly(heated)
    expect(described_class.call(scope, "Piscina")).to contain_exactly(collective, heated, generic, characteristic)
    expect(described_class.call(scope, "Hidromassagem")).to include(hot_tub)
  end

  ["Garden", "Lavabo", "Dependência de empregada", "Sol da manhã", "Sol da tarde", "Sol o dia todo"].each do |term|
    it "finds #{term} in unique features without relying on flags or orientation" do
      property = create(:habitation, tenant: tenant, garden_flag: false, lavabo_flag: false,
        face: nil, caracteristicas: {}, caracteristica_unica: [term])
      other = create(:habitation, tenant: tenant, garden_flag: false, lavabo_flag: false, face: nil)

      expect(described_class.call(scope, term)).to include(property)
      expect(described_class.call(scope, term)).not_to include(other)
    end
  end

  it "accepts characteristics stored as arrays for solar orientation and employee quarters" do
    property = create(:habitation, tenant: tenant, face: nil)
    property.update_columns(caracteristicas: ["Sol da manhã", "Dependência de empregada"])

    ["Sol da manhã", "Dependência de empregada"].each do |term|
      expect(described_class.call(scope, term)).to include(property)
    end
  end

  it "preserves numeric and tenant restrictions when combining the reported amenities" do
    attributes = {elevadores_qtd: 0, dormitorios_qtd: 3,
      caracteristicas: {"Churrasqueira" => "Churrasqueira"},
      infra_estrutura: ["Brinquedoteca", "Churrasqueira condomínio", "Elevador de serviço", "Piscina coletiva"]}
    complete = create(:habitation, tenant: tenant, **attributes)
    create(:habitation, tenant: tenant, **attributes.merge(dormitorios_qtd: 2))
    create(:habitation, tenant: Tenant.create!(name: "Outra conta", slug: "amenity-other"), **attributes)
    result = scope.where(dormitorios_qtd: 3)
    ["Churrasqueira", "Brinquedoteca", "Churrasqueira condomínio", "Elevador de serviço", "Piscina coletiva"].each do |term|
      result = described_class.call(result, term)
    end

    expect(result).to contain_exactly(complete)
  end
end
