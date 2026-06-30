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
    admin.tenant.attribute_options.create!(context: "habitation", category: "feature", name: "Vista mar")
    other_tenant.attribute_options.create!(context: "habitation", category: "feature", name: "Piscina externa")

    get admin_attribute_options_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Vista mar")
    expect(response.body).not_to include("Piscina externa")
  end

  it "cria atributo no tenant atual" do
    expect {
      post admin_attribute_options_path, params: {
        attribute_option: {
          context: "lead",
          category: "source",
          name: "Feira"
        }
      }
    }.to change { admin.tenant.attribute_options.count }.by(1)

    expect(admin.tenant.attribute_options.find_by!(name: "Feira")).to be_present
    expect(response).to redirect_to(admin_attribute_options_path)
  end
end
