require "rails_helper"

RSpec.describe "public_listing_nav_controller.js" do
  let(:source) { Rails.root.join("app/javascript/controllers/public_listing_nav_controller.js").read }

  it "navega paginação e sort só no frame da grade com advance" do
    expect(source).to include(
      'static values = { frame: String }',
      "Turbo.visit",
      '{ frame: this.frameValue, action: "advance" }',
      "closest(\"a[href]\")"
    )
  end
end
