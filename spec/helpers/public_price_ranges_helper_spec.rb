require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  let(:tenant) { Tenant.create!(name: "Busca", slug: "busca-faixas") }

  # public_tenant é helper_method do controller; não existe no helper spec.
  before do
    without_partial_double_verification { allow(helper).to receive(:public_tenant).and_return(tenant) }
  end

  it "usa as faixas personalizadas quando a conta personaliza" do
    PublicSiteProfile.new({ custom_price_ranges: "1", sale_price_ranges: "Até 2 mi|0|2000000" }, tenant: tenant).save

    expect(helper.public_price_range_options("venda")).to eq([["Todos os Valores", ""], ["Até 2 mi", "0-2000000"]])
  end

  it "usa as faixas do estoque quando não personalizadas e as padrão sem estoque suficiente" do
    allow(PublicSite::PriceRanges).to receive(:for).with(tenant).and_return("venda" => { min: 700_000, max: 21_100_000, step: 100_000, ranges: [["Até R$ 1,9 mi", "0-1900000"]], count: 50 })

    expect(helper.public_price_range_options("venda")).to eq([["Todos os Valores", ""], ["Até R$ 1,9 mi", "0-1900000"]])
    expect(helper.public_price_slider_bounds("venda")).to eq(min: 700_000, max: 21_100_000, step: 100_000)
    expect(helper.public_price_range_options("aluguel").second).to eq(["até R$5.000", "0-5000"])
    expect(helper.public_price_slider_bounds("aluguel")).to eq(min: 5_000, max: 50_000, step: 1_000)
  end
end
