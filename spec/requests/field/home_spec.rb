require "rails_helper"

RSpec.describe "Field::Home", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  it "mostra o botão de check-in para usuário ativo quando a feature está ligada" do
    Setting.set("field_checkin_enabled", "true")
    broker = create(:admin_user, name: "Thiago Dev")
    sign_in broker

    get field_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Fazer check-in agora")
    expect(response.body).to include("loja mais próxima")
  end

  it "oculta o botão de check-in para usuário bloqueado pontualmente" do
    Setting.set("field_checkin_enabled", "true")
    broker = create(:admin_user, name: "Thiago Dev")
    FieldFeatureGate.disable_agent!(broker, tenant: broker.tenant)
    sign_in broker

    get field_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Check-in indisponível")
    expect(response.body).not_to include("Fazer check-in agora")
  end

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
