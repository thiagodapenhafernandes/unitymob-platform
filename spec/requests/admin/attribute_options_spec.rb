require "rails_helper"

RSpec.describe "Admin::AttributeOptions", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "catalog-admin-#{SecureRandom.hex(6)}@salute.test") }
  let(:other_tenant) { Tenant.create!(name: "Outro catalogo #{SecureRandom.hex(3)}", slug: "outro-catalogo-#{SecureRandom.hex(3)}") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "lista apenas atributos do tenant atual" do
    current_tenant_name = "Vista mar #{SecureRandom.hex(4)}"
    other_tenant_name = "Piscina externa #{SecureRandom.hex(4)}"
    admin.tenant.attribute_options.create!(context: "habitation", category: "feature", name: current_tenant_name)
    other_tenant.attribute_options.create!(context: "habitation", category: "feature", name: other_tenant_name)

    get admin_attribute_options_path, params: { query: current_tenant_name }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(current_tenant_name)
    expect(response.body).not_to include(other_tenant_name)
  end

  it "renderiza o estado vazio compacto e acessível dentro da tabela" do
    get admin_attribute_options_path, params: { query: "sem-resultado-#{SecureRandom.hex(8)}" }

    expect(response).to have_http_status(:ok)
    empty_state = Nokogiri::HTML(response.body).at_css("td .ax-empty-state.ax-empty-state--compact")
    expect(empty_state).to be_present
    expect(empty_state["role"]).to eq("status")
    expect(empty_state["aria-live"]).to eq("polite")
    expect(empty_state.at_css(".ax-empty-state__icon[aria-hidden='true']")).to be_present
  end

  it "cria atributo no tenant atual" do
    attribute_name = "Feira #{SecureRandom.hex(4)}"

    expect {
      post admin_attribute_options_path, params: {
        attribute_option: {
          context: "lead",
          category: "source",
          name: attribute_name
        }
      }
    }.to change { admin.tenant.attribute_options.count }.by(1)

    expect(admin.tenant.attribute_options.find_by!(name: attribute_name)).to be_present
    expect(response).to redirect_to(admin_attribute_options_path)
  end
end
