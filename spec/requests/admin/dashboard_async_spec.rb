require "rails_helper"

RSpec.describe "Admin dashboard async slices", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  let(:admin) { create(:admin_user, :admin) }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza a visão geral sem carregar slices de outras áreas" do
    get admin_root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Visão geral", "Leads", "Imóveis")
    expect(response.body).to include('aria-current="page"')
    expect(response.body).not_to include('id="admin_dashboard_charts"')
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
    expect(response.body).to include("Visão geral", "Leads", "Imóveis")
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
    expect(response.body).to include("Visão geral", "Leads", "Imóveis")
  end

  it "carrega somente os painéis da aba Leads e preserva os filtros na URL" do
    get admin_root_path(tab: "leads", period: 7)

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.css(".ax-dashboard-skeleton")).not_to be_empty
    expect(document.css(".ax-skeleton-chart span").size).to eq(28)
    expect(document.css(".ax-skeleton-row b[class^='ax-skeleton-row__line--']")).not_to be_empty
    expect(document.css(".ax-dashboard-skeleton [style]")).to be_empty
    expect(document.css(".ax-dashboard-skeleton[role='status'][aria-live='polite'][aria-busy='true']")).not_to be_empty
    expect(document.css(".ax-skeleton-chart[aria-hidden='true'], .ax-skeleton-table[aria-hidden='true'], .ax-skeleton-list[aria-hidden='true']")).not_to be_empty
    expect(document.css(".ax-dashboard-skeleton").all? { |panel| panel["aria-label"].to_s.start_with?("Carregando ") }).to be(true)
    expect(response.body).to include('id="admin_dashboard_charts"')
    expect(response.body).to include('id="admin_dashboard_funnel"')
    expect(response.body).to include('id="admin_dashboard_status"')
    expect(response.body).to include('id="admin_dashboard_acquisition"')
    expect(response.body).to include('id="admin_dashboard_rankings"')
    expect(response.body).to include("tab=leads")
    expect(response.body).to include("period=7")
    expect(response.body).not_to include('id="admin_dashboard_operations"')
    expect(response.body).not_to include('id="admin_dashboard_support"')
    expect(response.body).not_to include("Atenção necessária")
  end

  it "separa os painéis de Imóveis" do
    get admin_root_path(tab: "properties")

    expect(response).to have_http_status(:ok)
    document = Nokogiri::HTML(response.body)
    expect(document.css(".ax-dashboard-properties-top > turbo-frame").size).to eq(2)
    expect(document.at_css(".ax-dashboard-properties-top--stacked > turbo-frame")[:id]).to eq("admin_dashboard_operations")
    expect(response.body).to include('id="admin_dashboard_rankings"')
    expect(response.body).to include('id="admin_dashboard_operations"')
    expect(response.body).to include('id="admin_dashboard_support"')
    expect(response.body).not_to include('id="admin_dashboard_charts"')
  end

  it "faz os painéis filtrados de Imóveis ocuparem toda a coluna disponível" do
    get admin_dashboard_section_path("rankings", tab: "properties"), headers: { "Turbo-Frame" => "admin_dashboard_rankings" }
    expect(response.body).to include("ax-dashboard-grid--rankings-single")

    get admin_dashboard_section_path("operations", tab: "properties"), headers: { "Turbo-Frame" => "admin_dashboard_operations" }
    expect(response.body).to include("ax-dashboard-grid--single")
  end

  it "oculta Campo quando o módulo está pausado e volta para a visão geral" do
    allow(Setting).to receive(:get).and_call_original
    allow(Setting).to receive(:get).with("field_checkin_enabled", "false").and_return("false")

    get admin_root_path(tab: "field")

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("<span>Campo</span>")
    expect(response.body).to include("Atenção necessária")
    expect(response.body).not_to include('id="admin_dashboard_operations"')
  end
  it "exibe os painéis de Campo quando o módulo está ativo" do
    allow(Setting).to receive(:get).and_call_original
    allow(Setting).to receive(:get).with("field_checkin_enabled", "false").and_return("true")

    get admin_root_path(tab: "field")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("<span>Campo</span>")
    expect(response.body).to include('id="admin_dashboard_rankings"')
    expect(response.body).to include('id="admin_dashboard_operations"')
    expect(response.body).not_to include('id="admin_dashboard_support"')
  end

  it "não mistura domínios dentro dos slices compartilhados" do
    allow(Setting).to receive(:get).and_call_original
    allow(Setting).to receive(:get).with("field_checkin_enabled", "false").and_return("true")

    get admin_dashboard_section_path("rankings", tab: "leads"), headers: { "Turbo-Frame" => "admin_dashboard_rankings" }
    expect(response.body).to include("Desempenho por corretor")
    expect(response.body).not_to include("Carteira de imóveis por corretor", "Top lojas por check-ins")

    get admin_dashboard_section_path("rankings", tab: "properties"), headers: { "Turbo-Frame" => "admin_dashboard_rankings" }
    expect(response.body).to include("Carteira de imóveis por corretor")
    expect(response.body).not_to include("Desempenho por corretor", "Top lojas por check-ins")

    get admin_dashboard_section_path("operations", tab: "field"), headers: { "Turbo-Frame" => "admin_dashboard_operations" }
    expect(response.body).to include("Atividade recente")
    expect(response.body).not_to include("Últimos imóveis atualizados")
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
    %w[charts acquisition funnel status rankings operations support].each do |section|
      get admin_dashboard_section_path(section), headers: { "Turbo-Frame" => "admin_dashboard_#{section}" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(id="admin_dashboard_#{section}"))
    end
  end

  it "resume aquisição e campanhas pagas no período" do
    create(:lead, tenant: admin.tenant, attribution_channel: "meta_ads", attribution_data: { "utm_campaign" => "verao", "utm_id" => "123" }, created_at: 2.days.ago)
    create(:lead, tenant: admin.tenant, attribution_channel: "direct", attribution_data: {}, created_at: 2.days.ago)

    get admin_dashboard_section_path("acquisition", period: 7), headers: { "Turbo-Frame" => "admin_dashboard_acquisition" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Origem dos leads")
    expect(response.body).to include("Taxa de atribuição")
    expect(response.body).to include("Meta Ads")
    expect(response.body).to include("verao")
    expect(response.body).to include("ID 123")
    expect(response.body).to include("ax-dashboard-campaign-grid")
    expect(response.body).to include("ax-dashboard-campaign-row__count")
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
    intake = create(
      :habitation,
      :broker_intake,
      tenant: admin.tenant,
      admin_user: admin,
      codigo: "dashboard-intake-draft",
      intake_status: "draft"
    )

    get admin_dashboard_section_path("support"), headers: { "Turbo-Frame" => "admin_dashboard_support" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(CGI.escapeHTML(edit_admin_captacao_path(intake)))
    expect(response.body).not_to include(CGI.escapeHTML(edit_admin_captacao_path(intake.id))) unless intake.to_param == intake.id.to_s
    expect(response.body).to include('data-turbo-frame="_top"')
  end

  it "filtra o catálogo pelo indicador de qualidade selecionado" do
    missing_price = create(:habitation, codigo: "dashboard-missing-price", valor_venda_cents: 0, valor_locacao_cents: 0)
    priced = create(:habitation, codigo: "dashboard-priced", valor_venda_cents: 900_000_00, valor_locacao_cents: 0)

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
    expect(Nokogiri::HTML(response.body).css(".ax-dashboard-funnel [style]")).to be_empty
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
    habitation = create(:habitation, tenant: admin.tenant, categoria: "Apartamento", codigo: "DASH-#{SecureRandom.hex(5)}")
    create(:lead, tenant: admin.tenant, property_id: habitation.id, created_at: 2.days.ago)

    get admin_dashboard_section_path("support", period: 7), headers: { "Turbo-Frame" => "admin_dashboard_support" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Oferta versus demanda por categoria")
    expect(response.body).to include("Apartamento")
    expect(response.body).to include("Leads vinculados")
    expect(Nokogiri::HTML(response.body).css("progress.ax-progress__bar")).not_to be_empty
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
