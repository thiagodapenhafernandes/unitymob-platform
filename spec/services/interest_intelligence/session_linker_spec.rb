require "rails_helper"

RSpec.describe InterestIntelligence::SessionLinker do
  it "links anonymous navigation to the converted lead and creates property interests" do
    lead = create(:lead)
    habitation = create(:habitation)
    session = PublicNavigationSession.create!(token: SecureRandom.uuid)
    event = session.events.create!(
      habitation: habitation,
      name: "property_view",
      path: "/imoveis/#{habitation.codigo}",
      property_snapshot: { city: habitation.cidade, category: habitation.categoria, price_cents: habitation.valor_venda_cents }
    )

    allow(Automation::Dispatcher).to receive(:dispatch)

    described_class.call(lead: lead, token: session.token)

    expect(session.reload.lead).to eq(lead)
    expect(event.reload.lead).to eq(lead)
    interest = ClientPropertyInterest.find_by(source_table: "public_navigation_events", source_key: event.id.to_s)
    expect(interest.lead_id).to eq(lead.id)
    expect(interest.habitation_id).to eq(habitation.id)
    expect(interest[:lead]).to eq(true)
    expect(Automation::Dispatcher).to have_received(:dispatch).with(
      :interest_profile_detected,
      lead,
      hash_including(source: "interest_intelligence")
    )
  end
end
