require "rails_helper"

RSpec.describe "admin/meta_integrations/_pages.html.erb", type: :view do
  it "renderiza fora do controller (broadcast do MetaSyncJob) sem o helper de impersonação" do
    expect(view).not_to respond_to(:impersonating_admin_user?)

    render "admin/meta_integrations/pages", pages: []

    html = Nokogiri::HTML(rendered)
    expect(html.at_css("#meta_pages")).to be_present
    expect(rendered).to include("Atualizar páginas")
    expect(rendered).to include("Buscar novos formulários", sync_forms_admin_meta_integrations_path)
    expect(rendered).not_to include("Selecionar páginas")
  end
  it "mantém a seleção de páginas acessível no HTML transmitido após sincronização" do
    integration = create(:user_meta_integration)
    page = create(:meta_facebook_page, user_meta_integration: integration)
    render "admin/meta_integrations/pages", pages: [], integration: integration
    expect(rendered).to include("Selecionar páginas", page.name, "Salvar seleção")
    expect(rendered).not_to include(integration.access_token, page.access_token)
  end

end
