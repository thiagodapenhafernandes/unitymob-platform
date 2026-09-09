require "rails_helper"

RSpec.describe "Lead mobile visibility", type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:admin_user, :admin) }
  let(:broker_profile) { Profile.create!(tenant: admin.tenant, name: "Mobile own", axis: "vertical", permissions: {"leads" => {"view" => true, "scope" => "own"}}) }
  let(:broker) { create(:admin_user, tenant: admin.tenant, profile: broker_profile) }
  let!(:owned) { create(:lead, tenant: admin.tenant, admin_user: broker, name: "Carteira corretor", status: "Novo") }
  let!(:unassigned) { create(:lead, tenant: admin.tenant, admin_user: nil, name: "Sem responsável", status: "Novo") }

  before { host! "localhost" }

  it "exibe para administrador os leads da conta em cards, contadores e paginação" do
    sign_in admin
    get admin_leads_path(view: "list", mobile_tab: "all")
    cards = Nokogiri::HTML(response.body).css('.lead-pwa-list .lead-pwa-card').map(&:text).join
    expect(cards).to include(owned.name, unassigned.name)
    get pwa_leads_page_admin_leads_path(mobile_tab: "all"), headers: {"Accept" => "application/json"}
    expect(response.parsed_body['html']).to include(owned.name, unassigned.name)
    expect(response.parsed_body['total']).to eq(2)
  end

  it "mantém o corretor restrito à própria carteira" do
    sign_in broker
    get admin_leads_path(view: "list", mobile_tab: "all")
    cards = Nokogiri::HTML(response.body).css('.lead-pwa-list .lead-pwa-card').map(&:text).join
    expect(cards).to include(owned.name)
    expect(cards).not_to include(unassigned.name)
    get pwa_leads_page_admin_leads_path(mobile_tab: "all"), headers: {"Accept" => "application/json"}
    expect(response.parsed_body['total']).to eq(1)
    expect(response.parsed_body['html']).not_to include(unassigned.name)
  end

  it "não inclui leads de outra conta" do
    other = Tenant.create!(name: "Outra conta mobile", slug: "other-mobile")
    outsider = create(:lead, tenant: other, name: "Outro tenant", status: "Novo")
    sign_in admin
    get pwa_leads_page_admin_leads_path(mobile_tab: "all"), headers: {"Accept" => "application/json"}
    expect(response.parsed_body['html']).not_to include(outsider.name)
    expect(response.parsed_body['total']).to eq(2)
  end
end
