require "rails_helper"

RSpec.describe "Funil CRM e GA4 no dashboard", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let!(:config) { Ga4ConversionConfig.create!(tenant: admin.tenant, enabled: true, api_secret: "send-secret", measurement_id: "G-TEST123", activated_at: 1.hour.ago) }
  before { host! "localhost"; sign_in admin }

  it "reutiliza o frame, filtros e mostra falta de configuração sem converter falha em zero" do
    get admin_root_path
    expect(response.body).to include('data-controller="ax-frame-refresh"')
    get admin_dashboard_section_path("funnel", period: 30), headers: { "Turbo-Frame" => "admin_dashboard_funnel" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Funil comercial e cobertura", "Conexão de leitura ainda não configurada", "Leads distintos")
    expect(response.body).not_to include("send-secret", "Impacto -&gt; venda")
    # Turbo rejeita um frame retornado cujo src aponta para a própria resposta.
    expect(Nokogiri::HTML(response.body).at_css("turbo-frame#admin_dashboard_funnel")["src"]).to be_nil
  end

  it "disponibiliza o mesmo painel sem configurar ou ativar GA4 na conta, inclusive Salute" do
    config.destroy!
    get admin_root_path
    expect(response.body).to include('data-controller="ax-frame-refresh"')
    get admin_dashboard_section_path("funnel"), headers: { "Turbo-Frame" => "admin_dashboard_funnel" }
    expect(response.body).to include("Funil comercial e cobertura", "Conexão de leitura ainda não configurada")
    expect(Ga4ConversionConfig.where(tenant: admin.tenant)).not_to exist
  end

  it "não consulta totais da propriedade quando há filtro de corretor" do
    expect(Ga4::ReportSnapshot).not_to receive(:call)
    get admin_dashboard_section_path("funnel", broker_ids: [admin.id]), headers: { "Turbo-Frame" => "admin_dashboard_funnel" }
    expect(response.body).to include("Remova os filtros de corretor")
  end

  it "mantém o escopo próprio do CRM e não expõe GA4 a usuário sem visão global" do
    profile = Profile.create!(tenant: admin.tenant, name: "Analista restrito", axis: "vertical", position: 600,
      permissions: { "dashboard" => { "view" => true }, "dashboard_leads" => { "view" => true }, "leads" => { "view" => true, "scope" => "own" } })
    user = create(:admin_user, tenant: admin.tenant, profile: profile)
    create(:lead, tenant: admin.tenant, admin_user: user, skip_automatic_routing: true)
    create(:lead, tenant: admin.tenant, admin_user: admin, skip_automatic_routing: true)
    sign_out admin
    sign_in user
    expect(Ga4::ReportSnapshot).not_to receive(:call)
    get admin_dashboard_section_path("funnel"), headers: { "Turbo-Frame" => "admin_dashboard_funnel" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Relatório da propriedade disponível ao titular")
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('table tbody tr:first-child td').text).to eq("1")
  end
end
