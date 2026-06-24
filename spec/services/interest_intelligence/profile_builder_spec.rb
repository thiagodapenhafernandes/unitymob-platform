require "rails_helper"

RSpec.describe InterestIntelligence::ProfileBuilder do
  it "builds a lead interest profile from public navigation" do
    lead = create(:lead)
    habitation = create(
      :habitation,
      cidade: "Balneário Camboriú",
      bairro: "Centro",
      categoria: "Apartamento",
      dormitorios_qtd: 3,
      valor_venda_cents: 900_000_00
    )
    session = PublicNavigationSession.create!(lead: lead, token: SecureRandom.uuid)
    session.events.create!(
      lead: lead,
      habitation: habitation,
      name: "property_view",
      path: "/imoveis/#{habitation.codigo}",
      property_snapshot: {
        city: "Balneário Camboriú",
        neighborhood: "Centro",
        category: "Apartamento",
        bedrooms: 3,
        price_cents: 900_000_00
      }
    )

    profile = described_class.call(lead).with_indifferent_access

    expect(profile[:criteria][:cities]).to include("Balneário Camboriú")
    expect(profile[:criteria][:neighborhoods]).to include("Centro")
    expect(profile[:criteria][:categories]).to include("Apartamento")
    expect(profile[:criteria][:bedrooms]).to eq(3)
    expect(profile[:confidence]).to be >= 60
  end
end
