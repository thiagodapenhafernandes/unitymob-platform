require "rails_helper"

RSpec.describe "Admin::AiIntegrations", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza o workspace operacional de IA" do
    get admin_ai_integration_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ai-integration-workspace")
    expect(response.body).to include("Configuração do provedor")
    expect(response.body).to include("Geração em lote")
    expect(response.body).to include("ax-progress")
    expect(response.body).not_to include("progress-bar")
    progress = Nokogiri::HTML(response.body).at_css(".ax-progress progress.ax-progress__bar")
    expect(progress).to be_present
    expect(progress["max"]).to eq("100")
    expect(progress["style"]).to be_nil
  end
end
