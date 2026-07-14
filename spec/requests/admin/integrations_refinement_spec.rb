require "rails_helper"

RSpec.describe "Admin integrations refinement", type: :request do
  include Devise::Test::IntegrationHelpers

  before do
    host! "localhost"
    sign_in create(:admin_user, :admin)
  end

  it "mantém DWV focada em configuração, comandos e monitoramento" do
    get admin_dwv_integrations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Configuração de Acesso")
    expect(response.body).to include("Controles de Sincronização")
    expect(response.body).to include("dwv_status_panel")
    expect(response.body).not_to include("Sobre a DWV")
    expect(response.body).not_to include("O que esta integração faz")
    status_frame = Nokogiri::HTML(response.body).at_css("#dwv_status_panel")
    expect(status_frame.css("[style]")).to be_empty
  end

  it "remove onboarding permanente da Meta" do
    get admin_meta_integrations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Conexão Facebook")
    expect(response.body).to include("ax-operational-panel", "meta-integration-connect-icon")
    expect(Nokogiri::HTML(response.body).at_css(".meta-integration-workspace").to_html).not_to match(/\bstyle\s*=/i)
    expect(response.body).not_to include("Como funciona?")
  end
end
