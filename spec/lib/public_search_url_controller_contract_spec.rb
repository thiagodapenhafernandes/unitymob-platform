require "rails_helper"

RSpec.describe "public_search_url_controller.js" do
  let(:source) { Rails.root.join("app/javascript/controllers/public_search_url_controller.js").read }

  it "delega a montagem da URL amigável ao servidor via marcador v=2" do
    expect(source).to include(
      'input[name="v"]',
      '"/imoveis"',
      "PublicSearch::ListingUrl"
    )
    expect(source).not_to include(
      "preventDefault",
      "window.location.href",
      "segmentFor",
      "friendlyPath"
    )
  end
end
