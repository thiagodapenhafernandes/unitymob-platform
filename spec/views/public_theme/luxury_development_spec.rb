require "rails_helper"

RSpec.describe "public_theme/_luxury_development_body.html.erb", type: :view do
  it "renderiza empreendimento luxury com dados da plataforma" do
    tenant = Tenant.create!(name: "Salute Imóveis", slug: "lux-dev")
    view.define_singleton_method(:public_tenant) { tenant }
    habitation = create(:habitation, tenant: tenant)
    assign(:habitation, habitation)
    assign(:development_units, [])

    render("public_theme/luxury_development_body")

    expect(rendered).to include("public-theme-development-hero--salute-luxury")
    expect(rendered).to include(habitation.display_title)
  end
end
