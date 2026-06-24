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
end
