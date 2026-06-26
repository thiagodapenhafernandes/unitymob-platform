require "rails_helper"

RSpec.describe "Admin::Captacoes dashboard", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

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
    expect(response.body).to include("capt-dashboard-workspace")
    expect(response.body).to include("capt-dashboard-filters")
    expect(response.body).to include("capt-dashboard-kpis")
    expect(response.body).not_to include("capt-dash-hero")
    expect(response.body).not_to include("capt-tv-toolbar")
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

  it "usa os últimos 7 dias como padrão do heatmap de leads e permite filtrar datas" do
    travel_to Time.zone.local(2026, 6, 26, 10, 0, 0) do
      create(:lead, admin_user: admin, created_at: Time.zone.local(2026, 6, 20, 9, 0, 0))
      create(:lead, admin_user: admin, created_at: Time.zone.local(2026, 6, 19, 9, 0, 0))
      create(:lead, admin_user: admin, created_at: Time.zone.local(2026, 6, 10, 9, 0, 0))

      get dashboard_admin_captacoes_path

      expect(response.body).to include("20/06")
      expect(response.body).to include("26/06")
      expect(response.body).not_to include("19/06")
      expect(response.body).not_to include("10/06")

      get dashboard_admin_captacoes_path, params: {
        heatmap_start_date: "2026-06-09",
        heatmap_end_date: "2026-06-10"
      }

      expect(response.body).to include("09/06")
      expect(response.body).to include("10/06")
      expect(response.body).not_to include("20/06")
      expect(response.body).not_to include("26/06")
    end
  end

  it "bloqueia o dashboard de captação para corretor" do
    broker_profile = Profile.create!(
      name: "Corretor #{SecureRandom.hex(6)}",
      permissions: Profile.default_permissions_for("Corretor")
    )
    broker = create(:admin_user, profile: broker_profile)

    sign_out admin
    sign_in broker

    get dashboard_admin_captacoes_path

    expect(response).to redirect_to(admin_root_path)
  end
end
