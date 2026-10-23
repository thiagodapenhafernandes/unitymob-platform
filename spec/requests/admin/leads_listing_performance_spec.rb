require "rails_helper"

RSpec.describe "Lista comercial otimizada", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin) }
  let(:tenant) { admin.tenant }

  before do
    host! "localhost"
    sign_in admin
  end

  it "preserva filtro, paginação e retorno ao lead sem alterar seu histórico" do
    customers = 12.times.map do |i|
      create(:lead, tenant: tenant, admin_user: admin, name: "Cliente #{i}", origin: "Portal teste", status: "Novo")
    end
    service = create(:lead, tenant: tenant, origin: "Portal teste", other_information: { "whatsapp_service_contact" => true })
    create(:lead, tenant: tenant, origin: "Outra origem")
    original = service.attributes

    get admin_leads_path(view: "list", origin: "Portal teste", page: 2)
    document = Nokogiri::HTML(response.body)
    rows = document.css(".lead-list-workspace article.ax-record-list__row")
    expect(rows.length).to eq(2)
    expect(rows.map { |row| row["id"].delete_prefix("lead_").to_i } - customers.map(&:id)).to be_empty
    link = rows.first.at_css("a.ax-record-name")
    return_to = Rack::Utils.parse_nested_query(URI.parse(link["href"]).query).fetch("return_to")
    uri = URI.parse(return_to)
    expect(uri.path).to eq(admin_leads_path)
    expect(Rack::Utils.parse_nested_query(uri.query)).to include("view" => "list", "origin" => "Portal teste", "page" => "2")
    expect(uri.fragment).to eq(rows.first["id"])

    get list_page_admin_leads_path(view: "list", origin: "Portal teste", offset: 10), headers: { "Accept" => "application/json" }
    expect(response.parsed_body).to include("total" => 12, "loaded_count" => 2, "has_more" => false)
    expect(service.reload.attributes).to eq(original)
  end
end
