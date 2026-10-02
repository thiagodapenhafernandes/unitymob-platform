require "rails_helper"

RSpec.describe MetaCampaignInsight, type: :model do
  let(:tenant) { create(:admin_user, :admin).tenant }

  it "exige campanha, data e linha única por dia" do
    described_class.create!(tenant: tenant, campaign_id: "c1", campaign_name: "Camp",
                            date: Date.current, spend: 10)

    expect(described_class.new(tenant: tenant)).not_to be_valid
    expect do
      described_class.create!(tenant: tenant, campaign_id: "c1", campaign_name: "Camp", date: Date.current)
    end.to raise_error(ActiveRecord::RecordInvalid)
  end
end
