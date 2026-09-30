require "rails_helper"

RSpec.describe "public.js currency-mask" do
  let(:pack) { Rails.root.join("app/javascript/public.js").read }
  let(:partial) { Rails.root.join("app/views/habitations/_advanced_filters_fields.html.erb").read }

  it "registra currency-mask no pack público (faixa de preço formata ao digitar)" do
    expect(pack).to include('["currency-mask", () => import("controllers/currency_mask_controller")]')
    expect(Rails.root.join("app/javascript/controllers/currency_mask_controller.js")).to exist
    expect(Rails.root.join("app/javascript/lib/currency_filter.js")).to exist
  end

  it "mantém a fiação data-controller nos campos de preço mínimo e máximo" do
    expect(partial.scan('controller: "currency-mask"').size).to eq(2)
    expect(partial).to include("input->currency-mask#format")
  end
end
