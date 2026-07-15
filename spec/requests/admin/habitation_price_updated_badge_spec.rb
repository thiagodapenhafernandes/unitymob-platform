require "rails_helper"

RSpec.describe "Admin::Habitations badge de preço atualizado", type: :request do
  include Devise::Test::IntegrationHelpers

  before do
    host! "localhost"
    sign_in create(:admin_user, :admin, email: "admin-#{SecureRandom.hex(8)}@salute.test")
  end

  it "mostra 'Preço atualizado há X dias' no card quando houve alteração de preço" do
    create(:habitation,
           codigo: "PRICE-#{SecureRandom.hex(4)}",
           titulo_anuncio: "Imóvel com preço atualizado",
           valor_venda_cents: 1_000_00,
           preco_atualizado_em: 3.days.ago)

    get admin_habitations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Preço atualizado há")
  end

  it "não mostra o badge quando o preço nunca foi alterado" do
    create(:habitation,
           codigo: "NOPRICE-#{SecureRandom.hex(4)}",
           titulo_anuncio: "Imóvel sem alteração de preço",
           valor_venda_cents: 1_000_00,
           preco_atualizado_em: nil)

    get admin_habitations_path

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Preço atualizado há")
  end
end
