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
  end

  it "renderiza cada slice em seu turbo frame" do
    %w[charts funnel status rankings operations support].each do |section|
      get admin_dashboard_section_path(section), headers: { "Turbo-Frame" => "admin_dashboard_#{section}" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(id="admin_dashboard_#{section}"))
    end
  end

  it "inclui o funil comercial em slice dedicado" do
    get admin_dashboard_section_path("funnel"), headers: { "Turbo-Frame" => "admin_dashboard_funnel" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Conversão comercial")
    expect(response.body).to include("Clientes impactados")
    expect(response.body).to include("Leads interessados")
    expect(response.body).to include("Oportunidades")
    expect(response.body).to include("Vendas")
  end

  it "inclui a pizza de status em slice dedicado" do
    get admin_dashboard_section_path("status"), headers: { "Turbo-Frame" => "admin_dashboard_status" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Leads por status")
    expect(response.body).to include("leadsStatusChart")
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
end
