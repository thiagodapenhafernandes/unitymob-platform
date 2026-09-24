require "rails_helper"

RSpec.describe "public_theme/_luxury_detail_body.html.erb", type: :view do
  it "renderiza detalhe luxury com dados da plataforma" do
    tenant = Tenant.create!(name: "Salute Imóveis", slug: "lux-detail")
    habitation = create(:habitation, tenant: tenant)
    assign(:habitation, habitation)
    assign(:public_map, nil)
    assign(:related_properties, [])

    render("public_theme/luxury_detail_body")

    expect(rendered).to include("public-theme-property-gallery--salute-luxury")
    expect(rendered).to include(habitation.display_title)
  end
end
