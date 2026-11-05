require "rails_helper"

RSpec.describe "Datas de reentrada dos leads", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let!(:lead) do
    create(:lead, tenant: admin.tenant, admin_user: admin, name: "Consulta Guanabara",
      created_at: Time.zone.parse("2026-02-21 16:26"), skip_automatic_routing: true)
  end
  let(:filters) { {view: "list", lead_tab: "all", start_date: "2026-10-12", end_date: "2026-10-18"} }

  before do
    host! "localhost"
    sign_in admin
    lead.activities.create!(kind: "inquiry_complemented", created_at: Time.zone.parse("2026-10-12 10:15"))
    lead.activities.create!(kind: "inquiry_complemented", created_at: Time.zone.parse("2026-11-01 09:00"))
  end

  it "mostra a consulta do período e a data original na lista e na paginação" do
    recent = create(:lead, tenant: admin.tenant, admin_user: admin, name: "Cadastro recente",
      created_at: Time.zone.parse("2026-10-12 09:00"), skip_automatic_routing: true)
    get admin_leads_path, params: filters
    expect(response).to have_http_status(:ok)
    row = Nokogiri::HTML(response.body).at_css("#lead_#{lead.id}")
    expect(row.text).to include("12/10/2026 10:15", "Cadastro: 21/02/2026 16:26")
    expect(row.text).not_to include("01/11/2026 09:00")
    rows = Nokogiri::HTML(response.body).css(".ax-record-list__row[id^='lead_']").map { |element| element["id"] }
    expect(rows.index("lead_#{lead.id}")).to be < rows.index("lead_#{recent.id}")

    get list_page_admin_leads_path, params: filters, headers: {"Accept" => "application/json"}
    expect(JSON.parse(response.body).fetch("html")).to include("12/10/2026 10:15")
  end

  it "exporta a mesma consulta em CSV e mantém o cadastro intacto" do
    get report_admin_leads_path, params: filters.merge(format: "csv")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Consulta Guanabara", "12/10/2026 10:15")
    expect(lead.reload.created_at).to eq(Time.zone.parse("2026-02-21 16:26"))
  end

  it "não exibe consulta de outra conta no mesmo período" do
    foreign = create(:lead, tenant: Tenant.create!(name: "Conta teste", slug: "entry-#{SecureRandom.hex(6)}"), name: "Não pode vazar", skip_automatic_routing: true)
    foreign.activities.create!(kind: "inquiry_complemented", created_at: Time.zone.parse("2026-10-12"))
    get admin_leads_path, params: filters
    expect(response.body).not_to include("Não pode vazar")
  end
end
