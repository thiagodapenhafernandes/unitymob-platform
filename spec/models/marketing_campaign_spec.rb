require "rails_helper"

RSpec.describe MarketingCampaign, type: :model do
  it "normaliza orçamento em formatos brasileiro, internacional e decimal simples" do
    campaign = described_class.new

    campaign.budget = "1.250,50"
    expect(campaign.budget_cents).to eq(125_050)

    campaign.budget = "1,250.50"
    expect(campaign.budget_cents).to eq(125_050)

    campaign.budget = "1250.50"
    expect(campaign.budget_cents).to eq(125_050)
  end
end
