require "rails_helper"

RSpec.describe InterestIntelligence::AiSummary do
  it "returns an explainable deterministic summary when OpenAI is not configured" do
    allow(Ai::PropertyContentService).to receive(:connected?).and_return(false)

    lead = create(:lead, name: "Maria")
    habitation = create(
      :habitation,
      titulo_anuncio: "Apartamento Centro",
      cidade: "Balneário Camboriú",
      bairro: "Centro",
      categoria: "Apartamento",
      dormitorios_qtd: 3,
      valor_venda_cents: 1_000_000_00
    )
    session = PublicNavigationSession.create!(lead: lead, token: SecureRandom.uuid)
    session.events.create!(
      lead: lead,
      habitation: habitation,
      name: "property_view",
      property_snapshot: {
        city: "Balneário Camboriú",
        neighborhood: "Centro",
        category: "Apartamento",
        bedrooms: 3,
        price_cents: 1_000_000_00
      }
    )

    summary = described_class.call(lead).with_indifferent_access

    expect(summary[:classification]).to be_present
    expect(summary[:summary]).to include("Maria")
    expect(summary[:broker_message]).to be_present
    expect(summary[:lead_message]).to be_present
    expect(summary[:rationale]).to be_an(Array)
  end
end
