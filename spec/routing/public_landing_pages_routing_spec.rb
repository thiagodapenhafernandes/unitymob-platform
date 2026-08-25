require "rails_helper"

RSpec.describe "public landing page routing", type: :routing do
  it "routes regular top-level slugs to public landing pages" do
    expect(get: "/apartamentos").to route_to(
      controller: "landing_pages",
      action: "show",
      slug: "apartamentos"
    )
  end

  it "keeps the admin namespace out of public landing page slugs" do
    expect(get: "/admin").to route_to(controller: "admin/dashboard", action: "index")
  end
end
