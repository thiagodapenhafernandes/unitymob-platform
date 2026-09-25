require "rails_helper"

RSpec.describe InterestIntelligence::Reprocessor do
  def navigation_event_for(lead, habitation)
    session = PublicNavigationSession.create!(token: SecureRandom.uuid)
    session.events.create!(
      lead: lead,
      habitation: habitation,
      name: "property_view",
      path: "/imoveis/#{habitation.codigo}",
      occurred_at: Time.current,
      property_snapshot: {}
    )
  end

  before { allow(Automation::Dispatcher).to receive(:dispatch) }

  it "cria interesse a partir do evento de navegação" do
    lead = create(:lead)
    habitation = create(:habitation)
    event = navigation_event_for(lead, habitation)

    result = described_class.call(lead: lead)

    expect(result.created_interests_count).to eq(1)
    interest = ClientPropertyInterest.find_by(
      source_table: "public_navigation_events",
      source_key: event.id.to_s
    )
    expect(interest.lead_id).to eq(lead.id)
    expect(interest.habitation_id).to eq(habitation.id)
  end

  it "é idempotente quando o evento já virou interesse" do
    lead = create(:lead)
    navigation_event_for(lead, create(:habitation))

    described_class.call(lead: lead)
    result = described_class.call(lead: lead)

    expect(result.created_interests_count).to eq(0)
    expect(ClientPropertyInterest.count).to eq(1)
  end

  it "resolve RecordNotUnique de jobs concorrentes sem explodir" do
    lead = create(:lead)
    navigation_event_for(lead, create(:habitation))

    calls = 0
    allow_any_instance_of(ClientPropertyInterest).to receive(:save!).and_wrap_original do |original, *args|
      calls += 1
      raise ActiveRecord::RecordNotUnique, "duplicate key value violates unique constraint" if calls == 1

      original.call(*args)
    end

    expect { described_class.call(lead: lead) }.not_to raise_error
    expect(ClientPropertyInterest.count).to eq(1)
  end
end
