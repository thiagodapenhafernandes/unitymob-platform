require "rails_helper"

RSpec.describe Lead, type: :model do
  describe "destroy" do
    it "keeps SEO conversion events and clears the lead reference" do
      lead = create(:lead)
      event = SeoConversionEvent.create!(
        lead: lead,
        event_type: "lead_created",
        occurred_at: Time.current
      )

      expect { lead.destroy! }.not_to raise_error
      expect(event.reload.lead_id).to be_nil
    end
  end
end
