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
end
