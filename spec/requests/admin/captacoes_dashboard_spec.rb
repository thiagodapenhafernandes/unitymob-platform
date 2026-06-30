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

  it "mostra atalho de metas por permissão funcional sem exigir Tenant Owner" do
    tenant = Tenant.create!(name: "Tenant metas #{SecureRandom.hex(3)}", slug: "tenant-metas-#{SecureRandom.hex(3)}")
    profile = Profile.create!(
      tenant: tenant,
      name: "Analista de metas #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 400,
      permissions: {
        "dashboard" => { "view" => true },
        "captacao_dashboard" => { "view" => true },
        "metas_captacao" => { "view" => true }
      }
    )
    analyst = create(:admin_user, tenant: tenant, profile: profile, role: :editor)

    sign_out admin
    sign_in analyst

    get dashboard_admin_captacoes_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(admin_captacao_goals_path)
    expect(response.body).to include("Metas")
    expect(response.body).not_to include("dashboardTitleModal")
  end

  it "respeita escopo de equipe e Tenant no heatmap de leads" do
    tenant = Tenant.create!(name: "Tenant heatmap #{SecureRandom.hex(3)}", slug: "tenant-heatmap-#{SecureRandom.hex(3)}")
    other_tenant = Tenant.create!(name: "Outro heatmap #{SecureRandom.hex(3)}", slug: "outro-heatmap-#{SecureRandom.hex(3)}")
    manager_profile = Profile.create!(
      tenant: tenant,
      name: "Manager heatmap #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 300,
      permissions: {
        "dashboard" => { "view" => true },
        "captacao_dashboard" => { "view" => true },
        "leads" => { "view" => true, "scope" => "team" }
      }
    )
    agent_profile = tenant.profiles.find_by!(key: "agent")
    other_profile = other_tenant.profiles.find_by!(key: "agent")
    manager = create(:admin_user, tenant: tenant, profile: manager_profile, role: :editor, name: "Gestor Heatmap")
    team_agent = create(:admin_user, tenant: tenant, profile: agent_profile, manager: manager, role: :editor, name: "Equipe Heatmap")
    outside_agent = create(:admin_user, tenant: other_tenant, profile: other_profile, role: :editor, name: "Outro Tenant Heatmap")
    create(:lead, tenant: tenant, admin_user: manager, created_at: Time.current)
    create(:lead, tenant: tenant, admin_user: team_agent, created_at: Time.current)
    create(:lead, tenant: other_tenant, admin_user: outside_agent, created_at: Time.current)

    sign_out admin
    sign_in manager

    get dashboard_admin_captacoes_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Gestor Heatmap")
    expect(response.body).to include("Equipe Heatmap")
    expect(response.body).not_to include("Outro Tenant Heatmap")
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
    broker_profile = Tenant.default.profiles.find_by!(key: "agent")
    broker_profile.update!(permissions: Profile.default_permissions_for("Corretor"))
    broker = create(:admin_user, profile: broker_profile)

    sign_out admin
    sign_in broker

    get dashboard_admin_captacoes_path

    expect(response).to redirect_to(admin_root_path)
  end
end
