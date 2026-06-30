require "rails_helper"

RSpec.describe "Admin::Proprietors", type: :request do
  include Devise::Test::IntegrationHelpers

  before { host! "localhost" }

  it "cria proprietário rápido e retorna payload para selecionar no cadastro do imóvel" do
    admin = create(:admin_user, :admin)
    sign_in admin

    expect {
      post quick_create_admin_proprietors_path,
           params: {
             proprietor: {
               name: "Proprietário Modal",
               phone_primary: "(47) 99999-1111",
               email: "modal@example.com"
             }
           },
           headers: { "ACCEPT" => "application/json" }
    }.to change(Proprietor, :count).by(1)

    expect(response).to have_http_status(:created)
    payload = JSON.parse(response.body)
    proprietor = Proprietor.last
    expect(payload).to include("id" => proprietor.id)
    expect(payload["name"]).to include("Proprietário Modal")
    expect(proprietor).to have_attributes(
      role: "owner",
      phone_primary: "(47) 99999-1111",
      email: "modal@example.com"
    )
  end

  it "permite criação rápida para perfil Administrativo" do
    internal_management_profile = Tenant.default.profiles.vertical.find_by!(name: Profile::INTERNAL_MANAGEMENT_PROFILE_NAME)
    administrative_profile = Tenant.default.profiles.find_by!(key: "administrativo")
    internal_management_profile.update!(
      permissions: Profile.default_permissions_for("Administrativo").merge(
        "proprietarios" => { "view" => true, "manage" => true }
      )
    )
    administrative_profile.update!(
      permissions: Profile.default_permissions_for("Administrativo").merge(
        "proprietarios" => { "view" => true, "manage" => true }
      )
    )
    administrative = create(:admin_user, profile: internal_management_profile, horizontal_profile: administrative_profile)
    sign_in administrative

    post quick_create_admin_proprietors_path,
         params: { proprietor: { name: "Proprietário Administrativo" } },
         headers: { "ACCEPT" => "application/json" }

    expect(response).to have_http_status(:created)
    expect(JSON.parse(response.body)["name"]).to eq("Proprietário Administrativo")
  end
end
