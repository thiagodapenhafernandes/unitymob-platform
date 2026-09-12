require "rails_helper"

RSpec.describe InterestIntelligence::FavoriteSync do
  let(:lead) { create(:lead) }
  let(:session) { PublicNavigationSession.create!(tenant: lead.tenant) }
  let(:property) { create(:habitation, tenant: lead.tenant) }

  it "vincula favoritos anteriores à conversão, sem duplicar, e registra remoções" do
    expect(described_class.call(session: session, ids: [property.id])).to eq(true)
    expect(session.events.last.metadata["initially_observed"]).to eq(true)
    expect { described_class.call(session: session, ids: [property.id]) }.not_to change(PublicNavigationEvent, :count)
    session.link_to_lead!(lead)
    expect(described_class.property_ids_for(lead)).to eq([property.id])
    expect(InterestIntelligence::ProfileBuilder.call(lead)[:property_ids]).to include(property.id)
    expect(session.events.last.reload.lead_id).to eq(lead.id)
    described_class.call(session: session, ids: [])
    expect(described_class.property_ids_for(lead)).to eq([])
    expect(session.events.last.name).to eq("property_favorite_removed")
    expect(InterestIntelligence::ProfileBuilder.call(lead)[:property_ids]).not_to include(property.id)
  end

  it "ignora imóveis de outra conta e rejeita payload inválido" do
    other = Tenant.create!(name: "Outra conta", slug: "favorite-#{SecureRandom.hex(4)}")
    foreign = create(:habitation, tenant: other)
    described_class.call(session: session, ids: [foreign.id, property.id])
    expect(session.reload.metadata["favorite_property_ids"]).to eq([property.id])
    expect { described_class.call(session: session, ids: ["x"]) }.to raise_error(ArgumentError)
    expect(session.link_to_lead!(create(:lead, tenant: other))).to eq(false)
    expect(session.reload.lead_id).to be_nil
    session.link_to_lead!(lead)
    expect(session.link_to_lead!(create(:lead, tenant: lead.tenant))).to eq(false)
    expect(session.reload.lead_id).to eq(lead.id)
  end
end
