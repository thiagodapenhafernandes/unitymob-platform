require "rails_helper"

RSpec.describe "admin/meta_integrations/_pages.html.erb", type: :view do
  it "renderiza fora do controller (broadcast do MetaSyncJob) sem o helper de impersonação" do
    expect(view).not_to respond_to(:impersonating_admin_user?)

    render "admin/meta_integrations/pages", pages: []

    html = Nokogiri::HTML(rendered)
    expect(html.at_css("#meta_pages")).to be_present
    expect(rendered).to include("Atualizar páginas")
    expect(rendered).not_to include("Selecionar páginas")
  end
end
