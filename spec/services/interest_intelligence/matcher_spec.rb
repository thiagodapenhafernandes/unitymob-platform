require "rails_helper"

RSpec.describe InterestIntelligence::Matcher do
  it "returns compatible properties using explainable criteria" do
    lead = create(:lead)
    viewed = create(
      :habitation,
      cidade: "Balneário Camboriú",
      bairro: "Centro",
      categoria: "Apartamento",
      dormitorios_qtd: 3,
      valor_venda_cents: 900_000_00
    )
    compatible = create(
      :habitation,
      cidade: "Balneário Camboriú",
      bairro: "Centro",
      categoria: "Apartamento",
      dormitorios_qtd: 3,
      valor_venda_cents: 950_000_00
    )
    create(
      :habitation,
      cidade: "Itajaí",
      bairro: "Fazenda",
      categoria: "Terreno",
      dormitorios_qtd: 0,
      valor_venda_cents: 400_000_00
    )

    session = PublicNavigationSession.create!(lead: lead, token: SecureRandom.uuid)
    session.events.create!(
      lead: lead,
      habitation: viewed,
      name: "property_view",
      property_snapshot: {
        city: viewed.read_attribute(:cidade),
        neighborhood: viewed.read_attribute(:bairro),
        category: viewed.categoria,
        bedrooms: viewed.dormitorios_qtd,
        price_cents: viewed.valor_venda_cents
      }
    )

    results = described_class.call(lead, limit: 10)

    expect(results.map(&:habitation)).to include(compatible)
    expect(results.find { |result| result.habitation == compatible }.reasons).to include("cidade compatível")
  end

  it "uses manually selected lead properties as profile signals" do
    lead = create(:lead)
    selected = create(
      :habitation,
      cidade: "Balneário Camboriú",
      bairro: "Centro",
      categoria: "Apartamento",
      dormitorios_qtd: 3,
      valor_venda_cents: 900_000_00
    )
    compatible = create(
      :habitation,
      cidade: "Balneário Camboriú",
      bairro: "Centro",
      categoria: "Apartamento",
      dormitorios_qtd: 3,
      valor_venda_cents: 930_000_00
    )
    lead.property_interests.create!(tenant: lead.tenant, habitation: selected)

    results = described_class.call(lead, limit: 10)

    expect(results.map(&:habitation)).to include(compatible)
    expect(results.map(&:habitation)).not_to include(selected)
  end
  it "usa locação mesmo quando o imóvel também está à venda e exclui imóveis só de venda" do
    lead = create(:lead, lead_type: "locacao")
    selected = create(:habitation, valor_venda_cents: 900_000_00, valor_locacao_cents: 3_000_00)
    compatible = create(:habitation, valor_venda_cents: 2_000_000_00, valor_locacao_cents: 3_100_00)
    sale_only = create(:habitation, valor_venda_cents: 3_100_00, valor_locacao_cents: 0)
    lead.property_interests.create!(tenant: lead.tenant, habitation: selected)

    matcher = described_class.new(lead, limit: 10)
    expect(matcher.profile.dig(:criteria, :business_type)).to eq("locacao")
    expect(matcher.profile.dig(:criteria, :max_price_cents)).to eq(3_000_00)
    results = matcher.call
    expect(results.map(&:habitation)).to include(compatible)
    expect(results.map(&:habitation)).not_to include(sale_only, selected)
    expect(results.find { |result| result.habitation == compatible }.reasons).to include("faixa de preço compatível")
  end

  it "encontra imóveis antigos além dos 250 recentes e mantém isolamento e limite" do
    lead = create(:lead)
    selected = create(:habitation)
    lead.property_interests.create!(tenant: lead.tenant, habitation: selected)
    best = create(:habitation, updated_at: 1.year.ago)
    template = build(:habitation, tenant: lead.tenant, categoria: "Terreno", valor_venda_cents: 100_00).attributes
    rows = 251.times.map do |index|
      template.except("id", "searchable_features").merge("codigo" => "MATCH-#{index}", "cidade" => best.cidade, "created_at" => Time.current, "updated_at" => Time.current)
    end
    Habitation.insert_all!(rows)
    foreign = create(:habitation, tenant: Tenant.create!(name: "Teste isolado", slug: "teste-isolado-#{SecureRandom.hex(4)}"))
    hidden = create(:habitation, exibir_no_site_flag: false)

    results = described_class.call(lead, limit: 1)
    expect(results.map(&:habitation)).to eq([best])
    expect(results.map(&:habitation)).not_to include(foreign, hidden, selected)
  end

  it "não sugere locação para um interesse explícito de compra" do
    lead = create(:lead, lead_type: "venda")
    selected = create(:habitation, valor_venda_cents: 900_000_00)
    rental = create(:habitation, valor_venda_cents: 0, valor_locacao_cents: 900_000_00)
    lead.property_interests.create!(tenant: lead.tenant, habitation: selected)
    expect(described_class.call(lead).map(&:habitation)).not_to include(rental)
  end
end
