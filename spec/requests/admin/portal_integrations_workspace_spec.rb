require "rails_helper"

RSpec.describe "Admin::PortalIntegrations workspace", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "prioriza navegação, configuração, feed e retornos sem blocos explicativos duplicados" do
    get admin_portal_integrations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("portal-integrations-nav")
    expect(response.body).to include("portal-integrations-commandbar")
    expect(response.body).to include("Configuração")
    expect(response.body).to include("URL do Feed para o portal")
    expect(response.body).to include("Últimos retornos do portal")
    expect(response.body).not_to include("Como ativar este portal")
    expect(response.body).not_to include("Checklist de configuração")
    expect(response.body).not_to include("Resumo do Feed")
  end
end
