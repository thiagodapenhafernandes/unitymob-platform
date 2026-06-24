require "rails_helper"

RSpec.describe InterestIntelligence::PropertyChangeDispatcher do
  include ActiveJob::TestHelper

  it "emits an interest event when a matched property price drops" do
    LayoutSetting.instance.update!(
      interest_intelligence_enabled: true,
      interest_intelligence_settings: InterestIntelligence::Settings::DEFAULTS
    )

    lead = create(:lead)
    habitation = create(:habitation, valor_venda_cents: 1_000_000_00)
    ClientPropertyInterest.create!(
      matched_lead: lead,
      habitation: habitation,
      source_table: "public_navigation_events",
      source_key: "property-price-drop-spec",
      lead: true
    )

    clear_enqueued_jobs

    expect do
      habitation.update!(valor_venda_cents: 940_000_00)
    end.to change(AutomationEvent.where(name: "interested_property_price_dropped"), :count).by(1)
      .and have_enqueued_job(Automation::ProcessEventJob)

    event = AutomationEvent.where(name: "interested_property_price_dropped").last
    expect(event.lead).to eq(lead)
    expect(event.source).to eq("interest_intelligence")
    expect(event.payload).to include(
      "habitation_id" => habitation.id,
      "new_price_cents" => 940_000_00,
      "old_price_cents" => 1_000_000_00
    )
  end
end
