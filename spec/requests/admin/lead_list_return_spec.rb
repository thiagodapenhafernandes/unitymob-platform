require "rails_helper"

RSpec.describe "Retorno dos leads da lista paginada", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }
  let(:filters) { { "q" => "Retorno", "origin" => "Site", "lead_tab" => "all", "view" => "list" } }

  before do
    host! "localhost"
    sign_in admin
  end

  it "volta do lote adicional para HTML com os filtros e a âncora do lead presente" do
    leads = 22.times.map do |i|
      create(:lead, tenant: admin.tenant, admin_user: admin, name: "Retorno #{i}", origin: "Site",
        status: "Novo", created_at: i.minutes.ago, skip_automatic_routing: true)
    end
    create(:lead, tenant: admin.tenant, admin_user: admin, name: "Outro contato", origin: "Site", skip_automatic_routing: true)

    get list_page_admin_leads_path(filters.merge("offset" => 20)), headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:ok)
    payload = JSON.parse(response.body)
    expect(payload["loaded_count"]).to eq(2)
    document = Nokogiri::HTML.fragment(payload.fetch("html"))
    detail_url = document.at_css(".ax-record-name")["href"]
    return_path = Rack::Utils.parse_nested_query(URI.parse(detail_url).query).fetch("return_to")
    uri = URI.parse(return_path)
    expect(uri.path).to eq(admin_leads_path)
    expect(Rack::Utils.parse_nested_query(uri.query)).to eq(filters.merge("page" => "3"))
    expect(uri.fragment).to eq("lead_#{leads[20].id}")

    get detail_url
    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).css("a").any? { |a| a["href"] == return_path }).to be(true)
    back_links = Nokogiri::HTML(response.body).css("a").select { |a| a.text.strip == "Voltar" }
    expect(back_links.size).to be >= 2
    expect(back_links.all? { |a| a["href"] == return_path }).to be(true)
    get [uri.path, uri.query].compact.join("?")
    expect(response.media_type).to eq("text/html")
    expect(Nokogiri::HTML(response.body).at_css("#lead_#{leads[20].id}")).to be_present
    expect(response.body).not_to include("Outro contato")
  end

  it "recupera links antigos sem abrir JSON nem perder a âncora" do
    lead = create(:lead, tenant: admin.tenant, admin_user: admin, skip_automatic_routing: true)
    old_path = list_page_admin_leads_path(filters.merge("offset" => 20, "anchor" => "lead_#{lead.id}"))
    expected = admin_leads_path(filters.merge("page" => 3, "anchor" => "lead_#{lead.id}"))
    get admin_lead_path(lead, return_to: old_path)
    expect(Nokogiri::HTML(response.body).css("a").any? { |a| a["href"] == expected }).to be(true)
    expect(Nokogiri::HTML(response.body).css("a").select { |a| a.text.strip == "Voltar" }.all? { |a| a["href"] == expected }).to be(true)

    get list_page_admin_leads_path(filters.merge("offset" => 20))
    expect(response).to redirect_to(admin_leads_path(filters.merge("page" => 3)))
  end
end
