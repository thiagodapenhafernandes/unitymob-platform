require "rails_helper"

RSpec.describe Lead, type: :model do
  describe ".origin_options" do
    it "combina catalogo manual com origens ja gravadas nos leads" do
      AttributeOption.create!(context: "lead", category: "source", name: "Instagram")
      create(:lead, origin: "Site")
      create(:lead, origin: "Google Ads")
      create(:lead, origin: "Site")

      expect(described_class.origin_options).to eq(["Google Ads", "Instagram", "Site"])
    end
  end

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
