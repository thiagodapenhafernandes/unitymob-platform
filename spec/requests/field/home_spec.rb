require "rails_helper"

RSpec.describe "Field::Home", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  it "direciona o atalho Imóveis para a aba Todos" do
    broker = create(:admin_user, :field_agent, name: "Luciana Indalécio")
    sign_in broker

    get field_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Imóveis")
    expect(response.body).to include(CGI.escapeHTML(admin_habitations_path(ownership: "all")))
  end
end
