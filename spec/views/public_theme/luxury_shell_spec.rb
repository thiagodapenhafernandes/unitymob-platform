require "rails_helper"

RSpec.describe "public_theme/_luxury_shell.html.erb", type: :view do
  it "renderiza header luxury com dados da plataforma" do
    tenant = Tenant.create!(name: "Salute Imóveis", slug: "lux-shell")
    view.define_singleton_method(:public_tenant) { tenant }
    view.define_singleton_method(:controller_name) { "home" }

    render("public_theme/luxury_shell") { "CORPO" }

    expect(rendered).to include("salute-luxury-theme")
    expect(rendered).to include("sl-header")
    expect(rendered).to include("Salute Imóveis")
    expect(rendered).to include("CORPO")
  end
end
