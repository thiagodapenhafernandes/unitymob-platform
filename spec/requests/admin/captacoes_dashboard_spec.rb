require "rails_helper"

RSpec.describe "Admin::Captacoes dashboard", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "calcula metas e indicadores de captação a partir dos imóveis" do
    create(:habitation, admin_user: admin, valor_venda_cents: 900_000_00, valor_locacao_cents: 0, regiao_foco: "Centro")
    create(:habitation, admin_user: admin, valor_venda_cents: 700_000_00, valor_locacao_cents: 0, regiao_foco: "Não")
    create(:habitation, admin_user: admin, valor_venda_cents: 0, valor_locacao_cents: 4_000_00, regiao_foco: "Sim", salute_rental_management_flag: true)
    create(:habitation, admin_user: admin, valor_venda_cents: 0, valor_locacao_cents: 3_000_00, regiao_foco: "Não", salute_rental_management_flag: false)

    get dashboard_admin_captacoes_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Região foco Venda")
    expect(response.body).to include("Região foco Locação")
    expect(response.body).to include("Captação com Adm")
    expect(response.body).to include("de 2 captações de venda")
    expect(response.body).to include("de 2 captações de locação")
    expect(response.body).to include("50%")
  end

  it "permite ao administrador editar o título do dashboard" do
    patch dashboard_title_admin_captacoes_path, params: {
      dashboard: {
        eyebrow: "Meta do mês",
        title: "Captação Salute"
      }
    }

    expect(response).to redirect_to(dashboard_admin_captacoes_path)
    follow_redirect!

    expect(response.body).to include("Meta do mês")
    expect(response.body).to include("Captação Salute")
  end
end
