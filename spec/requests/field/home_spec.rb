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

  it "mostra prioridades, dados do lead e ações de contato" do
    broker = create(:admin_user, :field_agent, name: "Thiago Dev")
    create(
      :lead,
      admin_user: broker,
      name: "Thiago do Lead",
      phone: "5521990872427",
      origin: "Meta Ads",
      status: Lead.status_value(:novo),
      created_at: 3.hours.ago
    )
    create(
      :habitation,
      :broker_intake,
      admin_user: broker,
      codigo: "field-home-#{SecureRandom.hex(6)}",
      intake_status: "draft",
      titulo_anuncio: "Apartamento Centro"
    )
    sign_in broker

    get field_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Prioridades")
    expect(response.body).to include("Leads sem contato")
    expect(response.body).to include("Leads a atender")
    expect(response.body).to include("Meta Ads")
    expect(response.body).to include("WhatsApp")
    expect(response.body).to include("tel:5521990872427")
    expect(response.body).to include("Captações abertas")
    expect(response.body).to include("Apartamento Centro")
  end
end
