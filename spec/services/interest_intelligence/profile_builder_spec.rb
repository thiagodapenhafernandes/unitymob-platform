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

  it "uses shared property link events and lead property interests as intelligence signals" do
    lead = create(:lead)
    broker = create(:admin_user, tenant: lead.tenant)
    viewed = create(
      :habitation,
      tenant: lead.tenant,
      cidade: "Balneário Camboriú",
      bairro: "Centro",
      categoria: "Apartamento",
      dormitorios_qtd: 3,
      valor_venda_cents: 1_100_000_00
    )
    interested = create(
      :habitation,
      tenant: lead.tenant,
      cidade: "Balneário Camboriú",
      bairro: "Centro",
      categoria: "Apartamento",
      dormitorios_qtd: 3,
      valor_venda_cents: 1_250_000_00
    )
    collection = lead.ai_property_share_collections.create!(admin_user: broker)
    collection.items.create!(habitation: viewed)
    collection.items.create!(habitation: interested)
    lead.property_interests.create!(tenant: lead.tenant, habitation: interested)
    collection.record!("collection_opened")
    collection.record!("property_opened", habitation: viewed)
    collection.record!("interest_created", lead:, habitation: interested, admin_user: broker)

    profile = described_class.call(lead).with_indifferent_access

    expect(profile[:signals][:property_views]).to eq(2)
    expect(profile[:signals][:explicit_interests]).to eq(1)
    expect(profile[:property_ids]).to include(viewed.id, interested.id)
    expect(profile[:criteria][:cities]).to include("Balneário Camboriú")
  end
end
