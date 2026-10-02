require "rails_helper"

RSpec.describe Admin::MetaCampaignsHelper, type: :helper do
  it "calcula custos e taxas sem dividir por zero ou tratar ausência de gasto como zero" do
    expect(helper.meta_campaign_cost(200, 4)).to eq("R$ 50,00")
    expect(helper.meta_campaign_cost(nil, 4)).to eq("—")
    expect(helper.meta_campaign_cost(200, 0)).to eq("—")
    expect(helper.meta_campaign_rate(1, 4)).to eq("25,0%")
    expect(helper.meta_campaign_rate(0, 0)).to eq("—")
  end
end
