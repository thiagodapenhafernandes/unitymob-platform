require "rails_helper"

RSpec.describe "Admin::Stores workspace", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:admin) { create(:admin_user, :admin, email: "stores-workspace-#{SecureRandom.hex(6)}@salute.test") }
  let!(:store) { create(:store, tenant: admin.tenant, name: "Unidade Centro #{SecureRandom.hex(3)}") }

  before do
    host! "localhost"
    sign_in admin
  end

  it "renderiza listagem, cadastro e edicao no cabecalho compartilhado" do
    get admin_stores_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-workspace-heading", "Operação · Lojas", store.name)
    expect(response.body).to include("Lojas da conta e configurações operacionais de check-in", "Ver loja #{store.name}", "Editar loja #{store.name}")

    get admin_store_path(store)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Resumo operacional da loja", store.name)

    get new_admin_store_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-workspace-heading", "Nova loja", "store_name")
    document = Nokogiri::HTML(response.body)
    expect(document.at_css('select[name="store[director_admin_user_id]"][data-controller="tom-select"]')).to be_present
    expect(document.at_css('select[name="store[timezone]"][data-controller="tom-select"] optgroup[label="Brasil"]')).to be_present
    expect(document.at_css('input[name="store[address]"][data-cep-lookup-target="address"]')).to be_present
    expect(document.at_css('input[name="store[latitude]"][data-store-map-picker-target="latitudeInput"][readonly]')).to be_present

    get edit_admin_store_path(store)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("ax-workspace-heading", "Editar loja", store.name, "store_name")
  end

  it "oculta acoes de gestao para perfil somente leitura e preserva o detalhe" do
    profile = admin.tenant.profiles.find_by!(key: "agent")
    profile.update!(permissions: profile.permissions.deep_merge("lojas" => { "view" => true, "manage" => false }))
    viewer = create(:admin_user, tenant: admin.tenant, profile: profile, name: "Leitor de lojas")
    sign_out admin
    sign_in viewer

    get admin_stores_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(store.name, "Ver loja #{store.name}")
    expect(response.body).not_to include("Nova loja", "Editar loja #{store.name}")

    get admin_store_path(store)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(edit_admin_store_path(store))

    get new_admin_store_path
    expect(response).to redirect_to(admin_root_path)
  end

  it "isola a listagem de lojas entre tenants" do
    other_tenant = Tenant.create!(name: "Outra conta #{SecureRandom.hex(3)}", slug: "outra-conta-#{SecureRandom.hex(3)}")
    other_store = create(:store, tenant: other_tenant, name: "Loja invisível #{SecureRandom.hex(3)}")

    get admin_stores_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(store.name)
    expect(response.body).not_to include(other_store.name)
  end
end
