require "rails_helper"

RSpec.describe "Admin context items", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "exibe atalhos de contexto apenas em paginas de item especifico" do
    habitation = create(:habitation, codigo: "CTXPIN-#{SecureRandom.hex(4)}")

    get edit_admin_habitation_path(habitation)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-context-pins")
    expect(response.body).to include("Imóvel #{habitation.codigo}")

    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("ax-context-pins")
    expect(response.body).not_to include("Imóvel #{habitation.codigo}")

    get admin_habitations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("ax-context-pins")
    expect(response.body).not_to include("Imóvel #{habitation.codigo}")
  end
end
