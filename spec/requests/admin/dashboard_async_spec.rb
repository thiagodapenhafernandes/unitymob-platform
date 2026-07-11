require "rails_helper"

RSpec.describe "Admin dashboard async slices", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza o shell com frames assíncronos" do
    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="admin_dashboard_charts"')
    expect(response.body).to include(admin_dashboard_section_path("charts"))
    expect(response.body).not_to include('id="admin_dashboard_charts" src="/admin/dashboard/charts" loading="lazy"')
    expect(response.body).to include('id="admin_dashboard_funnel"')
    expect(response.body).to include(admin_dashboard_section_path("funnel"))
    expect(response.body).to include('id="admin_dashboard_status"')
    expect(response.body).to include(admin_dashboard_section_path("status"))
    expect(response.body).to include('id="admin_dashboard_rankings"')
    expect(response.body).to include(admin_dashboard_section_path("rankings"))
    expect(response.body).to include('id="admin_dashboard_operations"')
    expect(response.body).to include(admin_dashboard_section_path("operations"))
    expect(response.body).to include('id="admin_dashboard_support"')
    expect(response.body).to include(admin_dashboard_section_path("support"))
    expect(response.body).to include("Atenção necessária")
    expect(response.body).to include("Prioridade operacional")
    expect(response.body).not_to include("Módulo Campo desativado")
  end

  it "permite dashboard principal para usuário operacional com permissão dashboard" do
    tenant = Tenant.create!(name: "Tenant dashboard #{SecureRandom.hex(3)}", slug: "tenant-dashboard-#{SecureRandom.hex(3)}")
    profile = Profile.create!(
      tenant: tenant,
      name: "Analista dashboard #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 600,
      permissions: {
        "dashboard" => { "view" => true },
        "imoveis" => { "view" => true, "scope" => "own" },
        "leads" => { "view" => true, "scope" => "own" },
        "captacoes" => { "view" => true, "scope" => "own" }
      }
    )
    user = create(:admin_user, tenant: tenant, profile: profile, role: :editor)

    sign_out admin
    sign_in user

    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="admin_dashboard_charts"')
    expect(response.body).not_to include(admin_profiles_path)
  end

  it "mantém usuário desktop sem permissão no workspace administrativo" do
    tenant = Tenant.create!(name: "Tenant sem dashboard #{SecureRandom.hex(3)}", slug: "tenant-sem-dashboard-#{SecureRandom.hex(3)}")
    profile = Profile.create!(
      tenant: tenant,
      name: "Sem dashboard #{SecureRandom.hex(3)}",
      axis: "vertical",
      position: 600,
      permissions: {
        "imoveis" => { "view" => true, "scope" => "own" }
      }
    )
    user = create(:admin_user, tenant: tenant, profile: profile, role: :editor)

    sign_out admin
    sign_in user

    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="admin_dashboard_charts"')
  end

  it "direciona usuário mobile sem permissão de dashboard para o Field" do
    tenant = Tenant.create!(name: "Tenant mobile #{SecureRandom.hex(3)}", slug: "tenant-mobile-#{SecureRandom.hex(3)}")
    profile = Profile.create!(tenant: tenant, name: "Field mobile #{SecureRandom.hex(3)}", axis: "vertical", position: 601, permissions: {})
    user = create(:admin_user, tenant: tenant, profile: profile, role: :editor)

    sign_out admin
    sign_in user
    get admin_root_path, headers: { "User-Agent" => "Mozilla/5.0 (Linux; Android 15) Mobile" }

    expect(response).to redirect_to(field_root_path)
  end

  it "renderiza cada slice em seu turbo frame" do
    %w[charts funnel status rankings operations support].each do |section|
      get admin_dashboard_section_path(section), headers: { "Turbo-Frame" => "admin_dashboard_#{section}" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(id="admin_dashboard_#{section}"))
    end
  end

  it "expõe indicadores acionáveis de qualidade do catálogo" do
    get admin_dashboard_section_path("operations"), headers: { "Turbo-Frame" => "admin_dashboard_operations" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Qualidade da publicação")
    expect(response.body).to include("Sem endereço")
    expect(response.body).to include("Sem fotos")
    expect(response.body).to include("Sem preço")
    expect(response.body).to include("Desatualizados há 90 dias")
    expect(response.body).to include("dashboard_quality=missing_address")
    expect(response.body).to include('data-turbo-frame="_top"')
  end

  it "usa o slug real da Habitation para abrir captações em rascunho fora do Turbo Frame" do
    intake = create(:habitation, :broker_intake, tenant: admin.tenant, admin_user: admin, intake_status: "draft")

    get admin_dashboard_section_path("support"), headers: { "Turbo-Frame" => "admin_dashboard_support" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(CGI.escapeHTML(edit_admin_captacao_path(intake)))
    expect(response.body).not_to include(CGI.escapeHTML(edit_admin_captacao_path(intake.id))) unless intake.to_param == intake.id.to_s
    expect(response.body).to include('data-turbo-frame="_top"')
  end

  it "filtra o catálogo pelo indicador de qualidade selecionado" do
    missing_price = create(:habitation, valor_venda_cents: 0, valor_locacao_cents: 0)
    priced = create(:habitation, valor_venda_cents: 900_000_00, valor_locacao_cents: 0)

    get admin_habitations_path(ownership: "all", dashboard_quality: "missing_price")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(missing_price.codigo)
    expect(response.body).not_to include(priced.codigo)
  end

  it "inclui o funil comercial em slice dedicado" do
    get admin_dashboard_section_path("funnel"), headers: { "Turbo-Frame" => "admin_dashboard_funnel" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Conversão comercial")
    expect(response.body).to include("Clientes impactados")
    expect(response.body).to include("Leads interessados")
    expect(response.body).to include("Oportunidades")
    expect(response.body).to include("Vendas")
    expect(response.body).to include("Referência:")
    expect(response.body).to include("%")
  end

  it "nomeia o ranking como distribuição de carteira e oculta Campo quando pausado" do
    allow(Setting).to receive(:get).with("field_checkin_enabled", "false").and_return("false")

    get admin_dashboard_section_path("rankings"), headers: { "Turbo-Frame" => "admin_dashboard_rankings" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Carteira de imóveis por corretor")
    expect(response.body).not_to include("Top corretores por imóveis")
    expect(response.body).not_to include("Top lojas por check-ins")
  end

  it "inclui a pizza de status em slice dedicado" do
    get admin_dashboard_section_path("status"), headers: { "Turbo-Frame" => "admin_dashboard_status" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Leads por status")
    expect(response.body).to include("leadsStatusChart")
    expect(response.body).to include("Abrir leads por status")
  end

  it "expõe KPIs como atalhos para as listagens correspondentes" do
    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Ver imóveis no catálogo")
    expect(response.body).to include("Ver leads recebidos hoje")
    expect(response.body).to include("Ver regras de distribuição")
  end

  it "propaga período e corretor para os slices do dashboard" do
    broker = create(:admin_user, tenant: admin.tenant)

    get admin_root_path(period: 7, broker_id: broker.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Escopo do painel")
    expect(response.body).to include("period=7")
    expect(response.body).to include("broker_id=#{broker.id}")
  end

  it "renderiza desempenho comercial no período selecionado" do
    broker = create(:admin_user, tenant: admin.tenant)
    create(:lead, tenant: admin.tenant, admin_user: broker, status: "Concluido", created_at: 2.days.ago)

    get admin_dashboard_section_path("rankings", period: 7), headers: { "Turbo-Frame" => "admin_dashboard_rankings" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Desempenho por corretor")
    expect(response.body).to include(broker.name)
    expect(response.body).to include("1 concluídos")
  end

  it "renderiza oferta versus demanda usando leads vinculados a imóveis" do
    habitation = create(:habitation, tenant: admin.tenant, categoria: "Apartamento")
    create(:lead, tenant: admin.tenant, property_id: habitation.id, created_at: 2.days.ago)

    get admin_dashboard_section_path("support", period: 7), headers: { "Turbo-Frame" => "admin_dashboard_support" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Oferta versus demanda por categoria")
    expect(response.body).to include("Apartamento")
    expect(response.body).to include("Leads vinculados")
  end

  it "gera a serie de leads dos ultimos 30 dias incluindo o dia atual" do
    travel_to Time.zone.local(2026, 6, 16, 10, 0, 0) do
      create(:lead, created_at: Time.zone.local(2026, 6, 16, 9, 0, 0))
      create(:lead, created_at: Time.zone.local(2026, 5, 18, 9, 0, 0))
      create(:lead, created_at: Time.zone.local(2026, 5, 17, 9, 0, 0))

      get admin_dashboard_section_path("charts"), headers: { "Turbo-Frame" => "admin_dashboard_charts" }
    end

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("&quot;2026-05-18&quot;")
    expect(response.body).to include("&quot;2026-06-16&quot;")
    expect(response.body).not_to include("&quot;2026-05-17&quot;")
    expect(response.body).to include("2 total")
  end

  it "permite selecionar um dia e agrupa as conversões pela hora de entrada do lead" do
    travel_to Time.zone.local(2026, 6, 16, 18, 0, 0) do
      create(:lead, created_at: Time.zone.local(2026, 6, 15, 9, 10, 0))
      create(:lead, created_at: Time.zone.local(2026, 6, 15, 9, 55, 0))
      create(:lead, created_at: Time.zone.local(2026, 6, 15, 17, 20, 0))
      create(:lead, created_at: Time.zone.local(2026, 6, 16, 9, 0, 0))

      get admin_dashboard_section_path("charts", lead_date: "2026-06-15"),
          headers: { "Turbo-Frame" => "admin_dashboard_charts" }
    end

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Leads por hora")
    expect(response.body).to include("3 total")
    expect(response.body).to include("&quot;09h&quot;,2")
    expect(response.body).to include("&quot;17h&quot;,1")
    expect(response.body).to include('data-dashboard-charts-leads-mode-value="hourly"')
    expect(response.body).to include('type="date"')
    expect(response.body).to include('value="2026-06-15"')
    expect(response.body).to include("30 dias")
  end

  it "ignora data horária fora da janela de 30 dias" do
    get admin_dashboard_section_path("charts", lead_date: 31.days.ago.to_date.iso8601),
        headers: { "Turbo-Frame" => "admin_dashboard_charts" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Leads — últimos 30 dias")
    expect(response.body).to include('data-dashboard-charts-leads-mode-value="daily"')
  end
end
