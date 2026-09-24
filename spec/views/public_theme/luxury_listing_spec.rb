require "rails_helper"

RSpec.describe "public_theme/components/_property_grid.html.erb", type: :view do
  it "renderiza cards luxury com dados da plataforma" do
    tenant = Tenant.create!(name: "Salute Imóveis", slug: "lux-grid")
    first = create(:habitation, tenant: tenant)
    create(:habitation, tenant: tenant)

    render("public_theme/components/property_grid", properties: Habitation.where(tenant: tenant).to_a, variant: "salute-luxury")

    expect(rendered).to include("public-theme-property-grid--salute-luxury")
    expect(rendered).to include(first.display_title)
  end

  it "mostra mensagem vazia sem imóveis" do
    render("public_theme/components/property_grid", properties: [], variant: "salute-luxury", empty_message: "Nada por aqui.")

    expect(rendered).to include("Nada por aqui.")
  end
end
